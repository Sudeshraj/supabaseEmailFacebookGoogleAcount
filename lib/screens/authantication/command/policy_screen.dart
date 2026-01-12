// lib/screens/policy_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/utils/policy_content.dart';

class PolicyScreen extends StatelessWidget {
  final bool isPrivacyPolicy;
  
  const PolicyScreen({
    super.key,
    required this.isPrivacyPolicy,
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
        backgroundColor: const Color(0xFF0F1820),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
        ),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Last Updated
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.update, color: Colors.white70, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    PolicyContent.lastUpdated,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Content with Markdown-style formatting
            _buildFormattedContent(content),
            
            const SizedBox(height: 40),
            
            // Back Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1877F3),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Back to Sign Up'),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // Link to other policy
            if (isPrivacyPolicy)
              TextButton(
                onPressed: () => context.go('/terms'),
                child: const Text(
                  'View Terms of Service',
                  style: TextStyle(color: Colors.blue),
                ),
              )
            else
              TextButton(
                onPressed: () => context.go('/privacy'),
                child: const Text(
                  'View Privacy Policy',
                  style: TextStyle(color: Colors.blue),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFormattedContent(String content) {
    final lines = content.split('\n');
    final widgets = <Widget>[];
    
    for (var line in lines) {
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 16));
        continue;
      }
      
      if (line.startsWith('### ')) {
        // Subheading
        widgets.add(
          Text(
            line.substring(4),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
        widgets.add(const SizedBox(height: 8));
      } else if (line.startsWith('- **') || line.startsWith('- ')) {
        // List item
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '• ',
                  style: TextStyle(color: Colors.white70),
                ),
                Expanded(
                  child: Text(
                    line.replaceFirst('- ', ''),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      } else if (line.startsWith('**') && line.endsWith('**')) {
        // Bold text
        widgets.add(
          Text(
            line.substring(2, line.length - 2),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      } else if (line.contains(':')) {
        // Key-value pair (like Email:)
        final parts = line.split(':');
        if (parts.length >= 2) {
          widgets.add(
            RichText(
              text: TextSpan(
                text: '${parts[0]}: ',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                children: [
                  TextSpan(
                    text: parts.sublist(1).join(':'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      } else if (int.tryParse(line.split('.')[0]) != null && line.contains('.')) {
        // Numbered list
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 4),
            child: Text(
              line,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
        );
      } else {
        // Regular paragraph
        widgets.add(
          Text(
            line,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              height: 1.6,
            ),
          ),
        );
      }
      
      widgets.add(const SizedBox(height: 8));
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }
}