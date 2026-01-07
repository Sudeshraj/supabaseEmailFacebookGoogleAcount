import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🔹 App Logo
              Image(
                image: AssetImage('assets/logo.png'),
                height: 120,
              ),

              SizedBox(height: 24),

              // 🔄 Loading indicator
              CircularProgressIndicator(),

              SizedBox(height: 16),

              Text(
                'LOADING',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
