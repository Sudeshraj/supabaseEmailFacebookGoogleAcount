import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _isVerified = false;
  bool _isSending = false;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _checkVerification();
  }

  Future<void> _checkVerification() async {
    await _auth.currentUser?.reload();
    setState(() {
      _isVerified = _auth.currentUser?.emailVerified ?? false;
    });

    if (_isVerified) {
      if (!mounted) return;
      // verified -> go to home
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  Future<void> _resendVerification() async {
    if (!mounted) return;
    setState(() => _isSending = true);

    await _auth.currentUser?.sendEmailVerification();

    if (!mounted) return;
    setState(() => _isSending = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Verification email resent 📩')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.email, color: Color(0xFF1877F3), size: 80),
                const SizedBox(height: 24),
                const Text(
                  'Check your email 📬',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'We’ve sent a verification link to your email. Click the link to verify your account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isSending ? null : _resendVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1877F3),
                    foregroundColor: Colors.white,
                  ),
                  child: _isSending
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Resend Email'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: _checkVerification,
                  child: const Text(
                    'Already verified? Continue →',
                    style: TextStyle(color: Colors.white70),
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
