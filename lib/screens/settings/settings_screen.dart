import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        children: [
          // Profile Management Section
          _buildSectionHeader('Profile Management'),
          
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_outline,
                color: Color(0xFFFF6B8B),
              ),
            ),
            title: const Text('Manage Profiles'),
            subtitle: const Text('Switch, deactivate, or delete profiles'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              context.push('/settings/profiles');
            },
          ),
          
          const Divider(),
          
          // Account Section
          _buildSectionHeader('Account'),
          
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person_outline, color: Colors.blue),
            ),
            title: const Text('Personal Information'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Navigate to personal info
            },
          ),
          
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.security_outlined, color: Colors.green),
            ),
            title: const Text('Privacy & Security'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Navigate to privacy
            },
          ),
          
          const Divider(),
          
          // Preferences Section
          _buildSectionHeader('Preferences'),
          
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_outlined, color: Colors.orange),
            ),
            title: const Text('Notifications'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Navigate to notifications
            },
          ),
          
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.language_outlined, color: Colors.purple),
            ),
            title: const Text('Language'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Navigate to language
            },
          ),
          
          const Divider(),
          
          // Support Section
          _buildSectionHeader('Support'),
          
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.help_outline, color: Colors.grey),
            ),
            title: const Text('Help & Support'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Navigate to help
            },
          ),
          
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.info_outline, color: Colors.grey),
            ),
            title: const Text('About'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              // Navigate to about
            },
          ),
          
          const SizedBox(height: 20),
          
          // Version
          Center(
            child: Text(
              'Version 1.0.0',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[400],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.grey[600],
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}