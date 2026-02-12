import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/utils/policy_content.dart';

class PolicyScreen extends StatelessWidget {
  final bool isPrivacyPolicy;
  final Map<String, dynamic>? extraData;

  const PolicyScreen({
    super.key,
    required this.isPrivacyPolicy,
    this.extraData,
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
          onPressed: () => _handleBack(context),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.update,
                    color: Colors.blue,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    PolicyContent.lastUpdated,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
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

  void _handleBack(BuildContext context) {
    // Simply pop to go back to DataConsentScreen
    // This preserves the state of DataConsentScreen
    if (GoRouter.of(context).canPop()) {
      GoRouter.of(context).pop();
    } else {
      // Fallback navigation
      context.go('/');
    }
  }

  void _handleDecline(BuildContext context) {
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
              Navigator.pop(context);
              _handleBack(context);
            },
            child: const Text(
              'Go Back',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
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

  void _handleAccept(BuildContext context) {
    // Record acceptance
    print('✅ ${isPrivacyPolicy ? 'Privacy Policy' : 'Terms of Service'} accepted');
    
    // Go back to DataConsentScreen
    _handleBack(context);
    
    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${isPrivacyPolicy ? 'Privacy Policy' : 'Terms of Service'} accepted',
        ),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }
}