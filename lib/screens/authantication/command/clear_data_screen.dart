// clear_data_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ClearDataScreen extends StatelessWidget {
  const ClearDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final screenWidth = MediaQuery.of(context).size.width;

    double calculateContainerWidth() {
      if (isMobile) {
        return screenWidth * 0.95;
      } else {
        final calculatedWidth = screenWidth * 0.45;
        return calculatedWidth < 500 ? calculatedWidth : 500.0;
      }
    }

    final containerWidth = calculateContainerWidth();

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Data Management',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20.0),
            child: Container(
              width: containerWidth,
              margin: EdgeInsets.all(isMobile ? 16.0 : 20.0),
              padding: EdgeInsets.all(isMobile ? 20.0 : 24.0),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.security,
                    size: isMobile ? 50.0 : 60.0,
                    color: Colors.blue.withOpacity(0.8),
                  ),
                  SizedBox(height: isMobile ? 16.0 : 20.0),
                  const Text(
                    'Data Management',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: isMobile ? 12.0 : 16.0),

                  // Data Collection Info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'What Data We Store:',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '• Email address (for account login)',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const Text(
                          '• App preferences and settings',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const Text(
                          '• Login session information',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'This data is stored locally on your device and can be cleared at any time.',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: isMobile ? 24.0 : 32.0),

                  // Clear Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF1E293B),
                            title: const Text(
                              'Confirm Clear Data',
                              style: TextStyle(color: Colors.white),
                            ),
                            content: const Text(
                              'This will remove all saved accounts, preferences, and login information from this device. This action cannot be undone.',
                              style: TextStyle(color: Colors.white70),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () async {
                                  Navigator.pop(context);

                                  // Show loading
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );

                                  // Clear data
                                  await SessionManager.clearAll();
                                  final supabase = Supabase.instance.client;
                                  await supabase.auth.signOut();
                                  appState.refreshState();

                                  // Navigate back
                                  if (context.mounted) {
                                    Navigator.pop(context); // Remove loading
                                    context.go('/');
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text(
                                  'Clear All',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        backgroundColor: Colors.red,
                      ),
                      child: Text(
                        'Clear All Data',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: isMobile ? 15.0 : 16.0,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: isMobile ? 16.0 : 20.0),

                  // Manage Preferences Button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        // Navigate to settings or preferences
                        context.pop();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        side: const BorderSide(color: Colors.white24),
                      ),
                      child: Text(
                        'Manage Preferences',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isMobile ? 15.0 : 16.0,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: isMobile ? 8.0 : 12.0),

                  // Privacy Policy Link
                  TextButton(
                    onPressed: () {
                      // Get current email from SessionManager if available
                      context.push(
                        '/privacy?from=${Uri.encodeComponent('/clear-data')}',
                      );
                    },
                    child: const Text(
                      'View Privacy Policy',
                      style: TextStyle(color: Colors.blue, fontSize: 14),
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
