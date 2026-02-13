import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ResetPasswordConfirmScreen extends StatelessWidget {
  final String email;

  const ResetPasswordConfirmScreen({
    super.key,
    required this.email,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: SafeArea(
        child: Center(
          child: Container(
            width: 400,
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:0.03),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.email_rounded,
                  color: Color(0xFF1877F3),
                  size: 60,
                ),
                
                const SizedBox(height: 20),
                
                const Text(
                  'Check Your Email',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                Text(
                  'We sent a password reset link to:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha:0.7),
                  ),
                ),
                
                const SizedBox(height: 8),
                
                Text(
                  email,
                  style: const TextStyle(
                    color: Color(0xFF1877F3),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                
                const SizedBox(height: 24),
                
                Text(
                  'Click the link in the email to reset your password.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha:0.7),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                ElevatedButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('Back to Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}