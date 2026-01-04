import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../authantication/command/multi_continue_screen.dart';

class EmployeeDashboard extends StatelessWidget {
  const EmployeeDashboard({super.key});

  // Future<void> _logout(BuildContext context) async {
  //   await FirebaseAuth.instance.signOut();
  //   // keep saved profiles — Facebook-style; remove if you want:
  //   // await SessionManager.clearAll();
  //   if (!Navigator.of(context).mounted) return;
  //   Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignInScreen()));
  // }

  Future<void> _logout(BuildContext context) async {
  try {
    // 🔴 1️⃣ Sign out from Firebase
    await FirebaseAuth.instance.signOut();

    // 🔵 2️⃣ Keep saved profiles for "Continue as ..." feature
    //  — You can clear them by uncommenting this if you want a full logout:
    // await SessionManager.clearAll();

    // 🟡 3️⃣ Wait a tiny moment to avoid navigation conflicts
    await Future.delayed(const Duration(milliseconds: 300));

    if (!context.mounted) return;

    // 🟢 4️⃣ Navigate to ContinueAs screen (instead of normal SignIn)
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const ContinueScreen()),
      (route) => false,
    );
  } catch (e) {
    if (!context.mounted) return;
    // ⚠️ 5️⃣ Show a beautiful alert dialog on error
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: const Color(0xFF1E2732),
        title: const Text(
          'Logout Failed 😕',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          e.toString(),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFF1877F3))),
          ),
        ],
      ),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final display = user?.displayName ?? user?.email ?? 'User';

    return Scaffold(
      appBar: AppBar(
        title: const Text('HomecE'),
        actions: [
          IconButton(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Text('Welcome, $display', style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}
