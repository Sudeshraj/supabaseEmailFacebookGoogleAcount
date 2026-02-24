// screens/auth/role_selector_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/session_manager.dart';

class RoleSelectorScreen extends StatefulWidget {
  final List<String> roles;
  final String email;
  final String userId;

  const RoleSelectorScreen({
    super.key,
    required this.roles,
    required this.email,
    required this.userId,
  });

  @override
  State<RoleSelectorScreen> createState() => _RoleSelectorScreenState();
}

class _RoleSelectorScreenState extends State<RoleSelectorScreen> {
  bool _isLoading = false;

  Future<void> _selectRole(String role) async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      print('🎯 User selected role: $role');
      
      // Save selected role to SessionManager
      await SessionManager.saveCurrentRole(role);
      
      // Update app state
      await appState.refreshState();
      
      if (!mounted) return;
      
      // Redirect based on selected role
      switch (role) {
        case 'owner':
          context.go('/owner');
          break;
        case 'barber':
          context.go('/barber');
          break;
        case 'customer':
          context.go('/customer');
          break;
        default:
          context.go('/');
          break;
      }
    } catch (e) {
      print('❌ Error selecting role: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting role: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose Your Role',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'You have multiple roles. Select how you want to continue.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              
              // Role buttons
              if (widget.roles.contains('owner'))
                _buildRoleButton(
                  title: 'Business Owner',
                  subtitle: 'Manage your salon, staff, and appointments',
                  icon: Icons.business_center,
                  color: const Color(0xFF4CAF50),
                  onTap: () => _selectRole('owner'),
                ),
              
              if (widget.roles.contains('owner') && widget.roles.contains('barber'))
                const SizedBox(height: 16),
              
              if (widget.roles.contains('barber'))
                _buildRoleButton(
                  title: 'Barber',
                  subtitle: 'View your schedule and manage appointments',
                  icon: Icons.person_outline,
                  color: const Color(0xFF2196F3),
                  onTap: () => _selectRole('barber'),
                ),
              
              if ((widget.roles.contains('owner') || widget.roles.contains('barber')) && 
                  widget.roles.contains('customer'))
                const SizedBox(height: 16),
              
              if (widget.roles.contains('customer'))
                _buildRoleButton(
                  title: 'Customer',
                  subtitle: 'Book appointments and manage your profile',
                  icon: Icons.people_outline,
                  color: const Color(0xFFFF9800),
                  onTap: () => _selectRole('customer'),
                ),
              
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withOpacity(0.2),
              color.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 20),
          ],
        ),
      ),
    );
  }
}