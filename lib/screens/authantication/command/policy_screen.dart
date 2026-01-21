// policy_screen.dart - Navigation fix
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/utils/policy_content.dart';

class PolicyScreen extends StatelessWidget {
  final bool isPrivacyPolicy;
  final String? returnRoute; // ✅ Add return route parameter

  const PolicyScreen({
    super.key,
    required this.isPrivacyPolicy,
    this.returnRoute, // ✅ Optional return route
  });

  @override
  Widget build(BuildContext context) {
    final title = isPrivacyPolicy 
        ? PolicyContent.privacyPolicyTitle 
        : PolicyContent.termsTitle;
    
    final content = isPrivacyPolicy 
        ? PolicyContent.privacyContent 
        : PolicyContent.termsContent;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => _handleBack(context), // ✅ Use helper method
        ),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Last Updated Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.blue.withOpacity(0.1),
              child: Text(
                PolicyContent.lastUpdated,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ),
            
            // Policy Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    content,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ),
            
            // Acceptance Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                border: Border(top: BorderSide(color: Colors.white24)),
              ),
              child: Column(
                children: [
                  const Text(
                    'By continuing, you acknowledge that you have read and understood this policy.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _handleDecline(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white24),
                          ),
                          child: const Text(
                            'Decline',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _handleAccept(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1877F3),
                          ),
                          child: const Text(
                            'I Accept',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ Helper method to handle back navigation
  void _handleBack(BuildContext context) {
    // Check if we have a specific return route
    if (returnRoute != null && returnRoute!.isNotEmpty) {
      context.go(returnRoute!);
    } else {
      // Default: Go back or to login screen
      if (GoRouter.of(context).canPop()) {
        context.pop();
      } else {
        context.go('/login');
      }
    }
  }

  // ✅ Handle decline button
  void _handleDecline(BuildContext context) {
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Decline Policy',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'You must accept our policies to use this app. Would you like to review them again?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _handleBack(context); // Navigate back
            },
            child: const Text(
              'Go Back',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              // Stay on policy screen
            },
            child: const Text(
              'Review Again',
              style: TextStyle(color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ Handle accept button
  void _handleAccept(BuildContext context) {
    // Record acceptance time
    final now = DateTime.now();
    print('✅ Policy accepted at: $now');
    
    // Navigate back or to appropriate screen
    _handleBack(context);
    
    // Show confirmation snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Policy accepted successfully'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }
}