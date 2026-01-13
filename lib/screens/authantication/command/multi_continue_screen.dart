import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/router/auth_gate.dart';
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
  // RESPONSIVE PASSWORD DIALOG
  // ============================================================
  Future<String?> _showPasswordDialog(String email) async {
    return await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return ResponsivePasswordDialog(email: email);
      },
    );
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
  appState.refreshState();
      await _processSuccessfulLogin(profile);
    } on AuthException catch (e) {
      if (!mounted) return;

      switch (e.code) {
        case 'invalid_login_credentials':
          await showCustomAlert(
            context: context,
            title: "Login Failed ❌",
            message: "Email or password is incorrect.",
            isError: true,
          );
          break;

        case 'email_not_confirmed':
          // await appState.restore();
          appState.refreshState();
          if (!mounted) return;
          context.go('/verify-email'); // 🔥 router → /verify-email
          break;

        case 'too_many_requests':
          await showCustomAlert(
            context: context,
            title: "Too Many Attempts ⏳",
            message: "Please wait a few minutes and try again.",
            isError: true,
          );
          break;

        default:
          await showCustomAlert(
            context: context,
            title: "Login Error ❌",
            message: e.message,
            isError: true,
          );
      }
      await _loadProfiles();
    } catch (e) {
      print('❌ Login error: $e');
      if (!mounted) return;

      await showCustomAlert(
        context: context,
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
      print('✅ Login successful! But email not verified.');
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

    // Save profile
    await SessionManager.saveUserProfile(
      email: dbProfile['email'] as String? ?? profile['email'] as String,
      userId: user.id,
      name: dbProfile['name'] as String? ?? dbProfile['email'].split('@').first,
      photo: dbProfile['photo'] as String?,
      roles: List<String>.from(profile['roles'] ?? []),
    );

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
  // EMAIL VERIFICATION DIALOG (NOT YOU DIALOG)
  // ============================================================
  Future<void> _showVerificationDialog(Map<String, dynamic> profile) async {
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1C1F26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Email Not Verified',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Please verify your email to continue.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Email: ${profile['email']}',
                style: const TextStyle(color: Colors.blueAccent, fontSize: 14),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                // Remove profile if not verified
                SessionManager.removeProfile(profile['email'] as String);
                _loadProfiles();
              },
              child: const Text(
                'Not You?',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/verify-email');
              },
              child: const Text('Verify Email'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // POPUP DELETE MENU
  // ============================================================
  void _showProfilesMenu(Offset position) async {
    if (profiles.isEmpty) return;

    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final selected = await showMenu<Map<String, dynamic>>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
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
  Future<void> clearAllProfiles() async {
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
            child: const Text("Clear All", style: TextStyle(color: Colors.red)),
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
    final isSelected = _selectedEmail == profile['email'];

    return GestureDetector(
      onTap: () => _handleAutoLogin(profile),
      child: Card(
        color: isSelected
            ? Colors.blue.withOpacity(0.15)
            : Colors.white.withOpacity(0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSelected
                ? Colors.blueAccent.withOpacity(0.5)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blueAccent.withOpacity(0.2),
            backgroundImage:
                (profile['photo'] != null &&
                    profile['photo'].toString().isNotEmpty)
                ? NetworkImage(profile['photo'] as String)
                : null,
            child:
                (profile['photo'] == null ||
                    (profile['photo'] as String).isEmpty)
                ? Icon(Icons.person, color: Colors.white.withOpacity(0.7))
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
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (profile['roles'] != null &&
                  (profile['roles'] as List).isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    (profile['roles'] as List).first.toString(),
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white38,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // UI - ORIGINAL FRAME
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
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  // Header with Three Dots Menu
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Continue',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      // Three Dots Menu Icon
                      if (profiles.isNotEmpty)
                        GestureDetector(
                          onTapDown: (details) =>
                              _showProfilesMenu(details.globalPosition),
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.more_vert,
                              color: Colors.white70,
                              size: 24,
                            ),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Subtitle
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      profiles.isEmpty
                          ? 'No saved profiles'
                          : '${profiles.length} saved profile${profiles.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Profiles List
                  Expanded(
                    child: _loading
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.blueAccent,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                const Text(
                                  'Logging in...',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                if (_selectedEmail != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      _selectedEmail!,
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.6),
                                        fontSize: 12,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : profiles.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person_add_disabled,
                                  size: 60,
                                  color: Colors.white.withOpacity(0.3),
                                ),
                                const SizedBox(height: 15),
                                Text(
                                  'No saved profiles',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.6),
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Login to save your profile',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.4),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            shrinkWrap: true,
                            itemCount: profiles.length,
                            itemBuilder: (context, index) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildProfileItem(
                                  profiles[index],
                                  index,
                                ),
                              );
                            },
                          ),
                  ),

                  // Footer Buttons
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Column(
                      children: [
                        // Login with another account
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              context.go('/login');
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Login with another account',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Create new account
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              // Go to signup page instead of RegistrationFlow
                              context.go('/signup');
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF1877F3)),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                            ),
                            child: const Text(
                              'Create new account',
                              style: TextStyle(
                                color: Color(0xFF1877F3),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),
                      ],
                    ),
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

// ============================================================
// RESPONSIVE PASSWORD DIALOG WIDGET
// ============================================================
class ResponsivePasswordDialog extends StatefulWidget {
  final String email;

  const ResponsivePasswordDialog({super.key, required this.email});

  @override
  State<ResponsivePasswordDialog> createState() =>
      _ResponsivePasswordDialogState();
}

class _ResponsivePasswordDialogState extends State<ResponsivePasswordDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _obscurePassword = true;
  Timer? _autoLoginTimer;

  @override
  void dispose() {
    _controller.dispose();
    _autoLoginTimer?.cancel();
    super.dispose();
  }

  void _checkAutoLogin(String password) {
    _autoLoginTimer?.cancel();

    // Auto login when password is 6+ characters and user pauses typing
    if (password.length >= 6) {
      _autoLoginTimer = Timer(const Duration(milliseconds: 500), () {
        Navigator.pop(context, password);
      });
    }
  }

  // ResponsivePasswordDialog widget එකේ build method එකේ
  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isWeb = screenSize.width > 700;

    // Calculate dialog width based on screen size
    double dialogWidth;
    double dialogMaxWidth;

    if (isWeb) {
      dialogWidth = screenSize.width * 0.25; // 25% of screen on web - smaller
      dialogMaxWidth = 350; // Even smaller max width
    } else {
      dialogWidth = screenSize.width * 0.85; // 85% of screen on mobile
      dialogMaxWidth = 400;
    }

    // Ensure dialog is not too small
    final double calculatedWidth = dialogWidth
        .clamp(300.0, dialogMaxWidth)
        .toDouble();

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
            // Title
            Text(
              'Enter Password',
              style: TextStyle(
                color: Colors.white,
                fontSize: isWeb ? 20 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // Email
            Text(
              'For:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: isWeb ? 14 : 13,
              ),
            ),
            Text(
              widget.email,
              style: TextStyle(
                color: Colors.blueAccent,
                fontSize: isWeb ? 14 : 13,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),

            SizedBox(height: isWeb ? 20 : 16),

            // Password Field
            TextField(
              controller: _controller,
              obscureText: _obscurePassword,
              autofocus: true,
              style: TextStyle(color: Colors.white, fontSize: isWeb ? 16 : 15),
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: TextStyle(
                  color: Colors.white70,
                  fontSize: isWeb ? 14 : 13,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: isWeb ? 16 : 14,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70,
                    size: isWeb ? 22 : 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              textInputAction: TextInputAction.done,
              onChanged: (value) {
                _checkAutoLogin(value);
              },
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.pop(context, value.trim());
                }
              },
            ),

            SizedBox(height: isWeb ? 16 : 12),

            // Auto Login Info
            Container(
              padding: EdgeInsets.all(isWeb ? 12 : 10),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    color: Colors.blueAccent,
                    size: isWeb ? 16 : 14,
                  ),
                  SizedBox(width: isWeb ? 8 : 6),
                  Expanded(
                    child: Text(
                      'Type password - auto login in 0.5s',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: isWeb ? 12 : 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: isWeb ? 20 : 16),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWeb ? 16 : 14,
                      vertical: isWeb ? 10 : 8,
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: isWeb ? 14 : 13,
                    ),
                  ),
                ),
                SizedBox(width: isWeb ? 10 : 8),
                ElevatedButton(
                  onPressed: () {
                    final enteredPassword = _controller.text.trim();
                    if (enteredPassword.isNotEmpty) {
                      Navigator.pop(context, enteredPassword);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: isWeb ? 20 : 18,
                      vertical: isWeb ? 12 : 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    'Login',
                    style: TextStyle(
                      fontSize: isWeb ? 14 : 13,
                      fontWeight: FontWeight.w600,
                    ),
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
