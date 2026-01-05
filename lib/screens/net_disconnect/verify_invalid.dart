import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class VerifyInvalidScreen extends StatelessWidget {
  const VerifyInvalidScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 80),
            const SizedBox(height: 16),
            const Text(
              'Email link is invalid or expired',
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                context.go('/login');
              },
              child: const Text('Back to Login'),
            ),
          ],
        ),
      ),
    );
  }
}
