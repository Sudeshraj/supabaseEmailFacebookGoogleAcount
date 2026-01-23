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
  bool _showComplianceDialog = false;

  // Add password controller here
  late TextEditingController _passwordController;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
    _checkCompliance();
    _passwordController = TextEditingController(); // Initialize here
  }

  @override
  void dispose() {
    _passwordController.dispose(); // Don't forget to dispose
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    // Load only profiles with remember me enabled
    final allProfiles = await SessionManager.getProfiles();
    final rememberMeProfiles = allProfiles
        .where((p) => p['rememberMe'] == true)
        .toList();
    if (!mounted) return;
    setState(() => profiles = rememberMeProfiles);
  }

  Future<void> _checkCompliance() async {
    final rememberMe = await SessionManager.isRememberMeEnabled();
    if (!rememberMe) {
      setState(() {
        _showComplianceDialog = true;
      });
    }
  }

// ============================================================
// SMART PASSWORD DIALOG WITH AUTO-SUBMIT (RESPONSIVE VERSION)
// ============================================================
Future<String?> _showPasswordDialog(String email) async {
  final passwordController = TextEditingController();
  bool obscurePassword = true;

  return await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      // Check screen size for responsiveness
      final isMobile = MediaQuery.of(context).size.width < 600;
      final screenWidth = MediaQuery.of(context).size.width;
      
      // Calculate dialog width with proper double type
      double calculateDialogWidth() {
        if (isMobile) {
          return screenWidth * 0.9; // 90% width on mobile
        } else {
          final calculatedWidth = screenWidth * 0.4;
          return calculatedWidth < 500 ? calculatedWidth : 500.0;
        }
      }
      
      final dialogWidth = calculateDialogWidth();

      return Dialog(
        backgroundColor: const Color(0xFF1C1F26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16.0 : (screenWidth - dialogWidth) / 2,
          vertical: 20.0,
        ),
        child: SizedBox(
          width: dialogWidth, // Responsive width
          child: StatefulBuilder(
            builder: (context, setState) {
              // Declare submit function FIRST
              void submitPassword(String password) {
                if (password.isEmpty) return;
                
                // Set submitting state
                setState(() {});
                
                // Close dialog with password after short delay
                Future.delayed(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    Navigator.pop(context, password);
                  }
                });
              }

              // Auto-submit function
              void checkAutoSubmit(String value) {
                if (value.length >= 6) {
                  // Auto-submit after 0.5 seconds of no typing
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (mounted && passwordController.text.length >= 6) {
                      submitPassword(passwordController.text.trim());
                    }
                  });
                }
              }

              return Padding(
                padding: EdgeInsets.all(isMobile ? 16.0 : 20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header - Responsive layout
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blueAccent.withOpacity(0.2),
                          radius: isMobile ? 18.0 : 20.0,
                          child: Icon(
                            Icons.person,
                            color: Colors.blueAccent,
                            size: isMobile ? 18.0 : 20.0,
                          ),
                        ),
                        SizedBox(width: isMobile ? 10.0 : 12.0),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Enter Password',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isMobile ? 15.0 : 16.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                email,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: isMobile ? 11.0 : 12.0,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    SizedBox(height: isMobile ? 16.0 : 20.0),
                    
                    // Password Field
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      autofocus: true,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 15.0 : 16.0,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 14.0 : 16.0,
                          vertical: isMobile ? 12.0 : 14.0,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: Colors.white70,
                            size: isMobile ? 20.0 : 24.0,
                          ),
                          onPressed: () {
                            setState(() => obscurePassword = !obscurePassword);
                          },
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onChanged: (value) {
                        checkAutoSubmit(value);
                        setState(() {}); // Update UI for hints
                      },
                      onSubmitted: (value) {
                        submitPassword(value.trim());
                      },
                    ),
                    
                    // Auto-submit hint
                    if (passwordController.text.isNotEmpty && passwordController.text.length < 6)
                      Padding(
                        padding: EdgeInsets.only(top: isMobile ? 6.0 : 8.0),
                        child: Text(
                          'Type ${6 - passwordController.text.length} more characters for auto-login',
                          style: TextStyle(
                            color: Colors.blueAccent.withOpacity(0.8),
                            fontSize: isMobile ? 10.0 : 11.0,
                          ),
                        ),
                      ),
                    
                    if (passwordController.text.length >= 6)
                      Padding(
                        padding: EdgeInsets.only(top: isMobile ? 6.0 : 8.0),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              color: Colors.greenAccent,
                              size: isMobile ? 12.0 : 14.0,
                            ),
                            SizedBox(width: isMobile ? 4.0 : 6.0),
                            Text(
                              'Auto-submit ready',
                              style: TextStyle(
                                color: Colors.greenAccent,
                                fontSize: isMobile ? 10.0 : 11.0,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    
                    SizedBox(height: isMobile ? 16.0 : 20.0),
                    
                    // Buttons - Responsive layout
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, null),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 14.0 : 16.0,
                              vertical: isMobile ? 8.0 : 10.0,
                            ),
                          ),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: isMobile ? 14.0 : 15.0,
                            ),
                          ),
                        ),
                        SizedBox(width: isMobile ? 8.0 : 10.0),
                        ElevatedButton(
                          onPressed: passwordController.text.isEmpty
                              ? null
                              : () {
                                  submitPassword(passwordController.text.trim());
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.blueAccent.withOpacity(0.5),
                            padding: EdgeInsets.symmetric(
                              horizontal: isMobile ? 18.0 : 20.0,
                              vertical: isMobile ? 10.0 : 12.0,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            'Login',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: isMobile ? 14.0 : 15.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    // Add some bottom padding on mobile for better UX
                    if (isMobile) const SizedBox(height: 8.0),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}

  // ============================================================
  // DIRECT PASSWORD LOGIN (NO EXTRA CONFIRMATION DIALOG)
  // ============================================================
  Future<void> _handleLogin(Map<String, dynamic> profile) async {
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

      print('🎯 PROFILE SELECTED: $email');

      // 1️⃣ FIRST TRY AUTO-LOGIN
      print('🔄 Checking for auto-login...');
      final autoLoginSuccess = await SessionManager.tryAutoLogin(email);

      if (autoLoginSuccess) {
        print('✅ AUTO-LOGIN SUCCESSFUL!');

        // Process successful login
        final supabase = Supabase.instance.client;
        final user = supabase.auth.currentUser;

        if (user != null) {
          // Save profile
          await SessionManager.saveUserProfile(
            email: email,
            userId: user.id,
            name: profile['name'] as String? ?? email.split('@').first,
            photo: profile['photo'] as String?,
            roles: List<String>.from(profile['roles'] ?? []),
            rememberMe: profile['rememberMe'] == true,
          );

          appState.refreshState();
          await _processSuccessfulLogin(profile);
          return;
        }
      }

      // 2️⃣ AUTO-LOGIN FAILED - SHOW PASSWORD DIALOG DIRECTLY
      print('⚠️ Auto-login not available, showing password dialog');

      // DIRECTLY SHOW PASSWORD DIALOG - NO EXTRA CONFIRMATION
      final password = await _showPasswordDialog(email);

      if (password == null || password.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      // 3️⃣ MANUAL LOGIN WITH PASSWORD
      print('🔄 Attempting manual login...');
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user == null) throw Exception("Login failed.");

      print('✅ MANUAL LOGIN SUCCESSFUL!');

      // Save profile
      await SessionManager.saveUserProfile(
        email: email,
        userId: user.id,
        name: profile['name'] as String? ?? email.split('@').first,
        photo: profile['photo'] as String?,
        roles: List<String>.from(profile['roles'] ?? []),
        rememberMe: profile['rememberMe'] == true,
      );

      // Update app state
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
          appState.emailVerifyerError();
          appState.refreshState();
          if (!mounted) return;
          context.go('/verify-email');
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

  // // ============================================================
  // // COMPLIANCE CONFIRMATION DIALOG
  // // ============================================================
  // // ============================================================
  // // SMART COMPLIANCE CONFIRMATION DIALOG
  // // ============================================================
  // Future<bool> _showComplianceConfirmation(String email) async {
  //   return await showDialog<bool>(
  //         context: context,
  //         barrierDismissible: false,
  //         builder: (context) {
  //           return AlertDialog(
  //             backgroundColor: const Color(0xFF1C1F26),
  //             shape: RoundedRectangleBorder(
  //               borderRadius: BorderRadius.circular(16),
  //             ),
  //             title: const Text(
  //               'Continue to Login',
  //               style: TextStyle(
  //                 color: Colors.white,
  //                 fontSize: 20,
  //                 fontWeight: FontWeight.bold,
  //               ),
  //             ),
  //             content: Column(
  //               mainAxisSize: MainAxisSize.min,
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //                 const Text(
  //                   'You selected:',
  //                   style: TextStyle(color: Colors.white70),
  //                 ),
  //                 const SizedBox(height: 8),
  //                 Text(
  //                   email,
  //                   style: const TextStyle(
  //                     color: Colors.blueAccent,
  //                     fontWeight: FontWeight.w500,
  //                   ),
  //                 ),
  //                 const SizedBox(height: 16),
  //                 Container(
  //                   padding: const EdgeInsets.all(12),
  //                   decoration: BoxDecoration(
  //                     color: Colors.blue.withOpacity(0.1),
  //                     borderRadius: BorderRadius.circular(8),
  //                     border: Border.all(
  //                       color: Colors.blueAccent.withOpacity(0.3),
  //                     ),
  //                   ),
  //                   child: const Column(
  //                     crossAxisAlignment: CrossAxisAlignment.start,
  //                     children: [
  //                       Row(
  //                         children: [
  //                           Icon(
  //                             Icons.auto_awesome,
  //                             size: 16,
  //                             color: Colors.blueAccent,
  //                           ),
  //                           SizedBox(width: 8),
  //                           Text(
  //                             'Auto-login attempted',
  //                             style: TextStyle(
  //                               color: Colors.white,
  //                               fontSize: 12,
  //                               fontWeight: FontWeight.w500,
  //                             ),
  //                           ),
  //                         ],
  //                       ),
  //                       SizedBox(height: 8),
  //                       Text(
  //                         'Please enter your password to continue.',
  //                         style: TextStyle(color: Colors.white70, fontSize: 12),
  //                       ),
  //                     ],
  //                   ),
  //                 ),
  //               ],
  //             ),
  //             actions: [
  //               TextButton(
  //                 onPressed: () => Navigator.pop(context, false),
  //                 child: const Text(
  //                   'Cancel',
  //                   style: TextStyle(color: Colors.white70),
  //                 ),
  //               ),
  //               ElevatedButton(
  //                 onPressed: () => Navigator.pop(context, true),
  //                 style: ElevatedButton.styleFrom(
  //                   backgroundColor: Colors.blueAccent,
  //                 ),
  //                 child: const Text('Enter Password'),
  //               ),
  //             ],
  //           );
  //         },
  //       ) ??
  //       false;
  // }

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
        .select('*')
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

    // Save profile with remember me
    final rememberMe = profile['rememberMe'] == true;
    await SessionManager.saveUserProfile(
      email: dbProfile['email'] as String? ?? profile['email'] as String,
      userId: user.id,
      name: dbProfile['name'] as String? ?? dbProfile['email'].split('@').first,
      photo: dbProfile['photo'] as String?,
      roles: List<String>.from(profile['roles'] ?? []),
      rememberMe: rememberMe,
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
  // EMAIL VERIFICATION DIALOG
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
          title: const Text(
            'Email Not Verified',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please verify your email to continue.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 16),
              Text(
                'Email: ${profile['email']}',
                style: const TextStyle(color: Colors.blueAccent, fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text(
                'You need to verify your email before accessing the app.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
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
                'Remove Account',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/verify-email');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
              ),
              child: const Text('Verify Email'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // BUILD PROFILE ITEM
  // ============================================================
  Widget _buildProfileItem(Map<String, dynamic> profile, int index) {
    final isSelected = _selectedEmail == profile['email'];
    final rememberMe = profile['rememberMe'] == true;

    return GestureDetector(
      onTap: () => _handleLogin(profile),
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
            backgroundColor: rememberMe
                ? Colors.blueAccent.withOpacity(0.2)
                : Colors.grey.withOpacity(0.2),
            backgroundImage:
                (profile['photo'] != null &&
                    profile['photo'].toString().isNotEmpty)
                ? NetworkImage(profile['photo'] as String)
                : null,
            child:
                (profile['photo'] == null ||
                    (profile['photo'] as String).isEmpty)
                ? Icon(
                    Icons.person,
                    color: rememberMe ? Colors.white : Colors.grey,
                  )
                : null,
          ),
          title: Row(
            children: [
              Text(
                profile['name'] as String? ?? 'Unknown',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (rememberMe)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.fingerprint,
                    color: Colors.greenAccent.withOpacity(0.8),
                    size: 16,
                  ),
                ),
            ],
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
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 18,
                ),
                onPressed: () async {
                  await _showDeleteConfirmation(profile);
                },
              ),
              const SizedBox(width: 4),
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
  // DELETE CONFIRMATION
  // ============================================================
  Future<void> _showDeleteConfirmation(Map<String, dynamic> profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1F26),
        title: const Text(
          "Remove Account?",
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Remove ${profile['email']} from this device?",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              "This will not delete your account, only remove it from this device.",
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
      await SessionManager.removeProfile(profile['email'] as String);
      await _loadProfiles();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${profile['email']} removed'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ============================================================
  // CLEAR ALL PROFILES WITH COMPLIANCE
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Remove all ${profiles.length} saved profiles from this device?",
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              "This will clear all saved login information and preferences.",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              "Your accounts will not be deleted, only removed from this device.",
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
            child: const Text("Clear All"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final profile in profiles) {
        await SessionManager.removeProfile(profile['email'] as String);
      }

      await SessionManager.clearContinueScreen();
      await SessionManager.setRememberMe(false);
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
  // UI - UPDATED FOR COMPLIANCE
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
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Continue',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            profiles.isEmpty
                                ? 'No saved profiles'
                                : '${profiles.length} profile${profiles.length == 1 ? '' : 's'} with Remember Me',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (profiles.isNotEmpty)
                        IconButton(
                          icon: const Icon(
                            Icons.delete_sweep,
                            color: Colors.redAccent,
                            size: 24,
                          ),
                          onPressed: clearAllProfiles,
                          tooltip: 'Clear All Profiles',
                        ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Compliance Notice
                  if (_showComplianceDialog)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.blueAccent.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blueAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Remember Me Disabled',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Enable "Remember Me" during login to save profiles',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

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
                                    color: Colors.white.withOpacity(0.6),
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

                        const SizedBox(height: 12),

                        // Clear all data button
                        TextButton(
                          onPressed: () => context.go('/clear-data'),
                          child: const Text(
                            'Clear All Data',
                            style: TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // Privacy links
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: () => context.go('/privacy'),
                              child: const Text(
                                'Privacy Policy',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 1,
                              height: 12,
                              color: Colors.white30,
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => context.go('/terms'),
                              child: const Text(
                                'Terms of Service',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Create new account
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
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
// SECURITY COMPLIANT PASSWORD DIALOG
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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_validatePassword);
  }

  void _validatePassword() {
    setState(() {
      _isValid = _controller.text.length >= 6;
    });
  }

  @override
  void dispose() {
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
            // Title
            const Text(
              'Enter Password',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            // Email
            Text(
              'For:',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
              ),
            ),
            Text(
              widget.email,
              style: const TextStyle(
                color: Colors.blueAccent,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 20),

            // Password Field
            TextField(
              controller: _controller,
              obscureText: _obscurePassword,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Password',
                labelStyle: const TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Colors.white.withOpacity(0.08),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.white70,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  Navigator.pop(context, value.trim());
                }
              },
            ),

            const SizedBox(height: 16),

            // Security Info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.security,
                    color: Colors.greenAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your password is securely encrypted',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
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
                  onPressed: _isValid
                      ? () {
                          final enteredPassword = _controller.text.trim();
                          if (enteredPassword.isNotEmpty) {
                            Navigator.pop(context, enteredPassword);
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.blueAccent.withOpacity(0.5),
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
