import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/utils/policy_content.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class PolicyScreen extends StatelessWidget {
  final bool isPrivacyPolicy;

  const PolicyScreen({
    super.key,
    required this.isPrivacyPolicy,
  });

  void _handleBack(BuildContext context) {
    if (GoRouter.of(context).canPop()) {
      GoRouter.of(context).pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final backgroundColor = context.backgroundColor;
    final textColor = context.textColor;
    final primaryColor = context.primaryColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: textColor,
          ),
          onPressed: () => _handleBack(context),
        ),
        title: Text(
          isPrivacyPolicy 
              ? PolicyContent.privacyPolicyTitle 
              : PolicyContent.termsTitle,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Last Updated - Using primaryColor
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: primaryColor.withValues(alpha: 0.1),
              child: Text(
                PolicyContent.lastUpdated,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: secondaryTextColor,
                  fontSize: 12,
                ),
              ),
            ),
            
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.grey.shade200,
                    ),
                  ),
                  child: Text(
                    isPrivacyPolicy 
                        ? PolicyContent.privacyContent 
                        : PolicyContent.termsContent,
                    style: TextStyle(
                      color: secondaryTextColor,
                      fontSize: 14,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}