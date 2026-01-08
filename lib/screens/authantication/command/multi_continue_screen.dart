import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/router/auth_gate.dart';
import 'package:flutter_application_1/alertBox/notyou.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

final supabase = Supabase.instance.client;

class ContinueScreen extends StatefulWidget {
  const ContinueScreen({super.key});

  @override
  State<ContinueScreen> createState() => _ContinueScreenState();
}

class _ContinueScreenState extends State<ContinueScreen> {
  List<Map<String, dynamic>> profiles = [];
  bool _loading = false;
  String? _selectedEmail;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    final list = await SessionManager.getProfiles();
    if (!mounted) return;
    setState(() => profiles = list);
  }

  // ============================================================
  // PASSWORD DIALOG - AUTO LOGIN ON TYPE
  // ============================================================
  Future<String?> _showPasswordDialog(String email) async {
    final completer = Completer<String?>();
    String? enteredPassword;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AutoLoginPasswordDialog(
          email: email,
          onPasswordEntered: (password) {
            enteredPassword = password;
            completer.complete(password);
            Navigator.pop(context);
          },
          onCancel: () {
            completer.complete(null);
            Navigator.pop(context);
          },
        );
      },
    );
    
    return completer.future;
  }

  // ============================================================
  // AUTO-LOGIN HANDLER
  // ============================================================
  Future<void> _handleAutoLogin(Map<String, dynamic> profile) async {
    if (_loading) return;
    
    setState(() {
      _loading = true;
      _selectedEmail = profile['email'] as String?;
    });

    try {
      final email = profile['email'] as String?;
      if (email == null) {
        setState(() => _loading = false);
        return;
      }

      print('🔄 Attempting auto login for: $email');
      
      // 1️⃣ TRY AUTO LOGIN FIRST
      final success = await SessionManager.tryAutoLogin(email);
      
      if (success) {
        await _processSuccessfulLogin(profile);
        return;
      }
      
      // 2️⃣ SHOW PASSWORD DIALOG
      final password = await _showPasswordDialog(email);
      
      if (password == null || password.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      
      // 3️⃣ MANUAL LOGIN
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) throw Exception("Login failed.");

      // Save profile
      await SessionManager.saveUserProfile(
        email: email,
        userId: user.id,
        name: profile['name'] as String? ?? email.split('@').first,
        photo: profile['photo'] as String?,
        roles: List<String>.from(profile['roles'] ?? []),
      );

      await _processSuccessfulLogin(profile);

    } on AuthException catch (e) {
      print('❌ Auth error: ${e.message}');
      if (!mounted) return;
      
      await showCustomAlert(
        context,
        title: "Login Failed",
        message: e.message,
        isError: true,
      );
      
      // await SessionManager.removeProfile(profile['email'] as String);
      await _loadProfiles();
      
    } catch (e) {
      print('❌ Login error: $e');
      if (!mounted) return;
      
      await showCustomAlert(
        context,
        title: "Connection Error",
        message: "Please check your internet connection.",
        isError: false,
      );
      
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _selectedEmail = null;
        });
      }
    }
  }

  // ============================================================
  // PROCESS SUCCESSFUL LOGIN
  // ============================================================
  Future<void> _processSuccessfulLogin(Map<String, dynamic> profile) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (user.emailConfirmedAt == null) {
      await _showVerificationDialog(profile);
      return;
    }

    final dbProfile = await supabase
        .from('profiles')
        .select('role, roles')
        .eq('id', user.id)
        .maybeSingle();

    if (dbProfile == null) {
      if (!mounted) return;
      context.go('/reg');
      return;
    }

    final role = AuthGate.pickRole(dbProfile['role'] ?? dbProfile['roles']);
    
    await SessionManager.saveUserRole(role);
    await SessionManager.updateLastLogin(profile['email'] as String);

    print('✅ Login successful! Role: $role');
    if (!mounted) return;

    switch (role) {
      case 'business':
        context.go('/owner');
        break;
      case 'employee':
        context.go('/employee');
        break;
      default:
        context.go('/customer');
    }
  }

  // ============================================================
  // EMAIL VERIFICATION DIALOG
  // ============================================================
  Future<void> _showVerificationDialog(Map<String, dynamic> profile) async {
    await showNotYouDialog(
      context: context,
      email: profile['email'] as String,
      name: profile['name'] as String? ?? 'Unknown User',
      photoUrl: profile['photo'] as String? ?? '',
      roles: [profile['role'] as String? ?? 'customer'],
      buttonText: 'Not You?',
      onContinue: () async {
        Navigator.of(context, rootNavigator: true).pop();
        if (navigatorKey.currentContext != null) {
          navigatorKey.currentContext!.go('/verify-email');
        }
      },
      onNotYou: () async {
        final nav = navigatorKey.currentState;
        if (nav == null) return;

        final dialogCtx = nav.overlay!.context;
        await showCustomAlert(
          dialogCtx,
          title: "Remove Profile?",
          message: "This profile will be removed from this device.",
          isError: true,
          buttonText: "Delete",
          onOk: () async {
            await SessionManager.removeProfile(profile['email'] as String);
            await _loadProfiles();
          },
        );
      },
    );
  }

  // ============================================================
  // POPUP DELETE MENU
  // ============================================================
  void _showProfilesMenu(Offset position) async {
    if (profiles.isEmpty) return;

    final selected = await showMenu<Map<String, dynamic>>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx, 
        position.dy, 
        position.dx + 40, 
        position.dy + 40,
      ),
      color: const Color(0xFF1C1F26),
      items: profiles
          .map(
            (p) => PopupMenuItem<Map<String, dynamic>>(
              value: p,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundImage:
                        (p['photo'] != null && p['photo'].toString().isNotEmpty)
                        ? NetworkImage(p['photo'].toString())
                        : null,
                    child: (p['photo'] == null || p['photo'].toString().isEmpty)
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p['name'] as String? ?? 'Unknown',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          p['email'] as String? ?? 'No Email',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () async {
                      await SessionManager.removeProfile(p['email'] as String);
                      _loadProfiles();
                      if (!mounted) return;
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );

    if (selected != null) {
      _handleAutoLogin(selected);
    }
  }

  // ============================================================
  // CLEAR ALL PROFILES
  // ============================================================
  Future<void> _clearAllProfiles() async {
    if (profiles.isEmpty) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          "Clear All Profiles?",
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          "Remove all ${profiles.length} saved profiles from this device?",
          style: const TextStyle(color: Colors.white70),
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
            child: const Text(
              "Clear All",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final profile in profiles) {
        await SessionManager.removeProfile(profile['email'] as String);
      }
      
      await SessionManager.clearContinueScreen();
      await _loadProfiles();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All profiles cleared'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ============================================================
  // BUILD PROFILE ITEM
  // ============================================================
  Widget _buildProfileItem(Map<String, dynamic> profile, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: Colors.blue.withOpacity(0.2),
          backgroundImage: (profile['photo'] != null &&
                  profile['photo'].toString().isNotEmpty)
              ? NetworkImage(profile['photo'] as String)
              : null,
          child: (profile['photo'] == null ||
                  (profile['photo'] as String).isEmpty)
              ? Icon(
                  Icons.person,
                  color: Colors.white.withOpacity(0.8),
                )
              : null,
        ),
        title: Text(
          profile['name'] as String? ?? 'Unknown',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: profile['email'] != null
            ? Text(
                profile['email'] as String,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
              )
            : null,
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: Colors.white38,
          size: 16,
        ),
        onTap: () => _handleAutoLogin(profile),
      ),
    );
  }

  // ============================================================
  // UI - SIMPLE RESPONSIVE DESIGN
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: SafeArea(
        child: Center(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isMobile ? double.infinity : 500,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 20 : 40,
              vertical: 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Continue',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (profiles.isNotEmpty)
                      IconButton(
                        icon: const Icon(
                          Icons.more_vert,
                          color: Colors.white70,
                          size: 28,
                        ),
                        onPressed: () {
                          _showProfilesMenu(
                            const Offset(0, 0), // Will be handled by tap
                          );
                        },
                      ),
                  ],
                ),
                
                const SizedBox(height: 10),
                
                Text(
                  'Select an account to continue',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Profiles List
                Expanded(
                  child: _loading
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const CircularProgressIndicator(
                                color: Colors.blue,
                              ),
                              const SizedBox(height: 20),
                              Text(
                                'Logging in...',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        )
                      : profiles.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.people_outline,
                                    size: 80,
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    'No saved profiles',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.6),
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    'Login to save your profile',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: profiles.length,
                              itemBuilder: (context, index) {
                                return _buildProfileItem(profiles[index], index);
                              },
                            ),
                ),
                
                // Buttons
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => context.go('/login'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Login with another account',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => context.go('/signup'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.blue),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Create new account',
                            style: TextStyle(color: Colors.blue),
                          ),
                        ),
                      ),
                      
                      if (profiles.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _clearAllProfiles,
                          child: const Text(
                            'Clear all profiles',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// AUTO LOGIN PASSWORD DIALOG
// ============================================================
class AutoLoginPasswordDialog extends StatefulWidget {
  final String email;
  final Function(String?) onPasswordEntered;
  final VoidCallback onCancel;
  
  const AutoLoginPasswordDialog({
    super.key,
    required this.email,
    required this.onPasswordEntered,
    required this.onCancel,
  });
  
  @override
  State<AutoLoginPasswordDialog> createState() => _AutoLoginPasswordDialogState();
}

class _AutoLoginPasswordDialogState extends State<AutoLoginPasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscureText = true;
  Timer? _debounceTimer;
  
  @override
  void dispose() {
    _controller.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }
  
  void _checkAndLogin(String password) {
    // Cancel previous timer
    _debounceTimer?.cancel();
    
    // Start new timer
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (password.length >= 6) { // Minimum password length
        widget.onPasswordEntered(password);
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            const Text(
              'Enter Password',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Email
            Text(
              'For: ${widget.email}',
              style: const TextStyle(
                color: Colors.blue,
                fontSize: 14,
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Password Field
            TextField(
              controller: _controller,
              obscureText: _obscureText,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureText ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureText = !_obscureText;
                    });
                  },
                ),
              ),
              onChanged: (value) {
                // Auto login when password length is sufficient
                if (value.length >= 6) {
                  _checkAndLogin(value);
                }
              },
              onSubmitted: (value) {
                if (value.isNotEmpty) {
                  widget.onPasswordEntered(value);
                }
              },
            ),
            
            const SizedBox(height: 16),
            
            // Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.blue,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Start typing password. Auto-login will trigger when password is complete.',
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: widget.onCancel,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    if (_controller.text.isNotEmpty) {
                      widget.onPasswordEntered(_controller.text);
                    }
                  },
                  child: const Text('Login'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}