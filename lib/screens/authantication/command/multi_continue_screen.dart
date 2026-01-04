import 'package:flutter/material.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/screens/commands/alertBox/notyou.dart';
import 'package:flutter_application_1/screens/commands/alertBox/show_custom_alert.dart';
import '../services/session_manager.dart';

import 'registration_flow.dart';
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
    setState(() => profiles = list);
  }

  Future<void> _handleProfileSelection(Map<String, dynamic> profile) async {
    if (_loading) return;
    setState(() => _loading = true);

    User? user = supabase.auth.currentUser;

    // Step 1: if not logged in yet, sign in
    if (user == null) {
      final savedPass = await SessionManager.getPassword(
        profile['email'],
        profile['role'],
      );
      if (savedPass != null) {
        try {
          final res = await supabase.auth.signInWithPassword(
            email: profile['email'],
            password: savedPass,
          );
          user = res.user;
        } on AuthException catch (e) {
          final msg = e.message.toLowerCase();

          // EMAIL NOT VERIFIED
          if (msg.contains("email not confirmed")) {
            setState(() => _loading = false);
            await _showVerificationDialog(profile);
            return;
          }
          if (!mounted) return;
          // INVALID LOGIN
          if (msg.contains("invalid login credentials")) {
            await showCustomAlert(
              context,
              title: "Login Failed",
              message: "Your email or password is incorrect.",
              isError: true,
            );
            setState(() => _loading = false);
            return;
          }

          await showCustomAlert(
            context,
            title: "Auth Error",
            message: e.message,
            isError: true,
          );
          setState(() => _loading = false);
          return;
        } catch (e) {
          if (!mounted) return;
          await showCustomAlert(
            context,
            title: "Server Error",
            message: "Please try again later.",
            isError: true,
          );
          setState(() => _loading = false);
          return;
        }
      }
    }

    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    // Step 2: check email verification
    final emailVerified = user.emailConfirmedAt != null;
    if (!emailVerified) {
      setState(() => _loading = false);
      await _showVerificationDialog(profile);
      return;
    }

    // Step 3: verified → redirect based on role
    final role = profile['role'];
    await SessionManager.saveUserRole(role);

    if (!mounted) return; //mounted true unoth false venava return venne naha,idiriyta code eka run ve. false unoth true vela return karanava evita code eka stop venava
    switch (role) {
      case "customer":
        context.go('/customer');
        break;
      case "business":
        context.go('/owner');
        break;
      case "employee":
        context.go('/employee');
        break;
      default:
        context.go('/customer');
    }

    setState(() => _loading = false);
  }

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

  // popup delete
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
                        ? NetworkImage(p['photo'])
                        : null,
                    child: (p['photo'] == null || p['photo'].toString().isEmpty)
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "${p['name']} (${p['role']})",
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () async {
                      await SessionManager.deleteRoleProfile(
                        p['email'],
                        p['role'],
                      );
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
      _handleProfileSelection(selected);
    }
  }

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
              child: Stack(
                children: [
                  if (profiles.isNotEmpty)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: GestureDetector(
                        onTapDown: (details) =>
                            _showProfilesMenu(details.globalPosition),
                        child: const Icon(
                          Icons.more_vert,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  Column(
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
                                  children: profiles
                                      .map(
                                        (p) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: GestureDetector(
                                            onTap: () =>
                                                _handleProfileSelection(p),
                                            child: Card(
                                              color: Colors.white.withValues(
                                                alpha: 0.06,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              elevation: 2,
                                              child: ListTile(
                                                leading: CircleAvatar(
                                                  radius: 25,
                                                  backgroundImage:
                                                      (p['photo'] != null &&
                                                          p['photo']
                                                              .toString()
                                                              .isNotEmpty)
                                                      ? NetworkImage(p['photo'])
                                                      : null,
                                                  child:
                                                      (p['photo'] == null ||
                                                          p['photo']
                                                              .toString()
                                                              .isEmpty)
                                                      ? const Icon(
                                                          Icons.person,
                                                          color: Colors.white,
                                                        )
                                                      : null,
                                                ),
                                                title: Text(
                                                  "${p['name']} (${p['role']} profile)",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                                trailing: const Icon(
                                                  Icons
                                                      .arrow_forward_ios_rounded,
                                                  color: Colors.white38,
                                                  size: 18,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),
                        ),
                      ),
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {
                                context.go('/login');
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white24),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
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
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const RegistrationFlow(),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xFF1877F3),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
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
                    ],
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
