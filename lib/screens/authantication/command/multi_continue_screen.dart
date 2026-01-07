import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/router/auth_gate.dart';
import 'package:flutter_application_1/screens/authantication/services/singup_session.dart';
import 'package:flutter_application_1/screens/commands/alertBox/notyou.dart';
import 'package:flutter_application_1/screens/commands/alertBox/show_custom_alert.dart';
import '../services/session_manager.dart';

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
  // MAIN HANDLER (SINGLE CLEAN FLOW)
  // ============================================================
  Future<void> _handleProfileSelection(Map<String, dynamic> profile) async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      User? user = supabase.auth.currentUser;

      // --------------------------------------------------
      // 1️⃣ LOGIN IF NEEDED
      // --------------------------------------------------
      // if (user == null) {
      //   final savedPass =
      //       await SessionManagerto.getPassword(profile['email']);
      //   if (savedPass == null) {
      //     setState(() => _loading = false);
      //     return;
      //   }

      //   final res = await supabase.auth.signInWithPassword(
      //     email: profile['email'],
      //     password: savedPass,
      //   );

      //   user = res.user;
      // }

      if (user == null) {
        final password = await _showPasswordDialog(profile['email']);
        if (password == null || password.isEmpty) return;

        final res = await supabase.auth.signInWithPassword(
          email: profile['email'],
          password: password,
        );

        user = res.user;
        if (user == null) throw Exception("Login failed");
      }

      // if (user == null) {
      //   setState(() => _loading = false);
      //   return;
      // }

      // --------------------------------------------------
      // 2️⃣ FETCH PROFILE
      // --------------------------------------------------
      final profileOne = await supabase
          .from('profiles')
          .select('role, roles')
          .eq('id', user.id)
          .maybeSingle();

      // ❌ No profile → registration
      if (profileOne == null) {
        if (!mounted) return;
        context.go('/reg');
        return;
      }

      // --------------------------------------------------
      // 3️⃣ EMAIL VERIFY CHECK
      // --------------------------------------------------
      if (user.emailConfirmedAt == null) {
        setState(() => _loading = false);
        await _showVerificationDialog(profile);
        return;
      }

      // --------------------------------------------------
      // 4️⃣ ROLE PICK + SAVE
      // --------------------------------------------------
      final role = AuthGate.pickRole(profileOne['role'] ?? profileOne['roles']);

      await SessionManager.saveUserRole(role);

      if (!mounted) return;

      // --------------------------------------------------
      // 5️⃣ FINAL REDIRECT
      // --------------------------------------------------
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
    } on AuthException catch (e) {
      if (!mounted) return;

      await showCustomAlert(
        context,
        title: "Login Error ❌",
        message: e.message,
        isError: true,
      );
    } catch (_) {
      if (!mounted) return;

      await showCustomAlert(
        context,
        title: "Server Error",
        message: "Please try again later.",
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _showPasswordDialog(String email) async {
    String? password;
    await showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text('Enter password for $email'),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                password = controller.text.trim();
                Navigator.pop(context);
              },
              child: const Text('Login'),
            ),
          ],
        );
      },
    );
    return password;
  }

  // ============================================================
  // EMAIL VERIFY DIALOG
  // ============================================================
  Future<void> _showVerificationDialog(Map<String, dynamic> profile) async {
    await showNotYouDialog(
      context: context,
      email: profile['email'],
      name: profile['name'] ?? 'Unknown User',
      photoUrl: profile['photo'] ?? '',
      roles: [profile['role']],
      buttonText: 'Not You?',
      onContinue: () async {
        Navigator.of(context, rootNavigator: true).pop();
        navigatorKey.currentContext!.go('/verify-email');
      },
      onNotYou: () async {
        final nav = navigatorKey.currentState;
        if (nav == null) return;

        final dialogCtx = nav.overlay!.context;
        await showCustomAlert(
          dialogCtx,
          title: "Remove Profile?",
          message: "This role profile will be removed from this device.",
          isError: true,
          buttonText: "Delete",
          onOk: () async {
            await SessionManager.deleteRoleProfile(
              profile['email'],
              profile['role'],
            );
            await supabase.auth.signOut();
            _loadProfiles();
          },
        );
      },
    );
  }

  // ============================================================
  // UI (UNCHANGED)
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
                  Expanded(
                    child: Center(
                      child: profiles.isEmpty
                          ? const Text(
                              'No saved profiles',
                              style: TextStyle(color: Colors.white60),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: profiles.map((p) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: GestureDetector(
                                    onTap: () => _handleProfileSelection(p),
                                    child: Card(
                                      color: Colors.white.withValues(
                                        alpha: 0.06,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundImage:
                                              (p['photo'] != null &&
                                                  p['photo']
                                                      .toString()
                                                      .isNotEmpty)
                                              ? NetworkImage(p['photo'])
                                              : null,
                                          child:
                                              (p['photo'] == null ||
                                                  p['photo'].toString().isEmpty)
                                              ? const Icon(
                                                  Icons.person,
                                                  color: Colors.white,
                                                )
                                              : null,
                                        ),
                                        title: Text(
                                          "${p['name']} (${p['role']})",
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                        ),
                                        trailing: const Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          color: Colors.white38,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Login with another account'),
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
