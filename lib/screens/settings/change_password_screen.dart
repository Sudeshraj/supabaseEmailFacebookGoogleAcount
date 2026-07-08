// screens/settings/change_password_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/auth_provider_service.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final AuthProviderService _authService = AuthProviderService();

  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // Password strength
  bool _hasMinLength = false;
  bool _hasUpperCase = false;
  bool _hasLowerCase = false;
  bool _hasNumber = false;
  bool _hasSpecialChar = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _validatePassword(String password) {
    setState(() {
      _hasMinLength = password.length >= 6;
      _hasUpperCase = password.contains(RegExp(r'[A-Z]'));
      _hasLowerCase = password.contains(RegExp(r'[a-z]'));
      _hasNumber = password.contains(RegExp(r'[0-9]'));
      _hasSpecialChar = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));
    });
  }

  double _getPasswordStrength() {
    int count = 0;
    if (_hasMinLength) count++;
    if (_hasUpperCase) count++;
    if (_hasLowerCase) count++;
    if (_hasNumber) count++;
    if (_hasSpecialChar) count++;
    return count / 5;
  }

  String _getPasswordStrengthText() {
    final strength = _getPasswordStrength();
    if (strength <= 0.2) return 'Weak';
    if (strength <= 0.4) return 'Fair';
    if (strength <= 0.6) return 'Good';
    if (strength <= 0.8) return 'Strong';
    return 'Very Strong';
  }

  Color _getPasswordStrengthColor() {
    final strength = _getPasswordStrength();
    if (strength <= 0.2) return Colors.red;
    if (strength <= 0.4) return Colors.orange;
    if (strength <= 0.6) return Colors.yellow.shade700;
    if (strength <= 0.8) return Colors.lightGreen;
    return Colors.green;
  }

  Future<void> _handleChangePassword() async {
    final currentPassword = _currentPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    // ✅ Validation
    if (currentPassword.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your current password';
        _successMessage = null;
      });
      return;
    }

    if (newPassword.length < 6) {
      setState(() {
        _errorMessage = 'Password must be at least 6 characters';
        _successMessage = null;
      });
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() {
        _errorMessage = 'Passwords do not match';
        _successMessage = null;
      });
      return;
    }

    if (currentPassword == newPassword) {
      setState(() {
        _errorMessage = 'New password must be different from current password';
        _successMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final success = await _authService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      if (success) {
        setState(() {
          _successMessage = '✅ Password changed successfully!';
          _isLoading = false;
          _currentPasswordController.clear();
          _newPasswordController.clear();
          _confirmPasswordController.clear();

          // Reset password strength indicators
          _hasMinLength = false;
          _hasUpperCase = false;
          _hasLowerCase = false;
          _hasNumber = false;
          _hasSpecialChar = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Password changed successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );

        // ✅ Navigate back after success
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.pop(context, true);
          }
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final bool isWeb = screenSize.width > 700;
    // ✅ FIX: Convert num to double
    final double maxWidth = isWeb ? 480.0 : double.infinity;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () {
            if (_isLoading) return;
            Navigator.pop(context);
          },
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ✅ Header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFF6B8B,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.lock_outline,
                                  color: Color(0xFFFF6B8B),
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Change Password',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Password must be at least 6 characters',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.white.withValues(
                                          alpha: 0.7,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ✅ Error/Success Messages
                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (_successMessage != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.green.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  color: Colors.green,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _successMessage!,
                                    style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // ✅ Current Password
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Current Password',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _currentPasswordController,
                                obscureText: _obscureCurrent,
                                enabled: !_isLoading,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Enter current password',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(
                                    alpha: 0.05,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.lock_outline,
                                    color: Colors.white54,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureCurrent
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.white54,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureCurrent = !_obscureCurrent;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ✅ New Password
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'New Password',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _newPasswordController,
                                obscureText: _obscureNew,
                                enabled: !_isLoading,
                                onChanged: _validatePassword,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Enter new password',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(
                                    alpha: 0.05,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.lock_outline,
                                    color: Colors.white54,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureNew
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.white54,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureNew = !_obscureNew;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ✅ Password Strength Indicator
                        if (_newPasswordController.text.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Password Strength:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.white.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: _getPasswordStrength(),
                                          backgroundColor: Colors.white
                                              .withValues(alpha: 0.1),
                                          color: _getPasswordStrengthColor(),
                                          minHeight: 6,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _getPasswordStrengthText(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _getPasswordStrengthColor(),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    _buildRequirementChip(
                                      '6+ characters',
                                      _hasMinLength,
                                    ),
                                    _buildRequirementChip(
                                      'Uppercase',
                                      _hasUpperCase,
                                    ),
                                    _buildRequirementChip(
                                      'Lowercase',
                                      _hasLowerCase,
                                    ),
                                    _buildRequirementChip('Number', _hasNumber),
                                    _buildRequirementChip(
                                      'Special char',
                                      _hasSpecialChar,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 16),

                        // ✅ Confirm Password
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Confirm New Password',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _confirmPasswordController,
                                obscureText: _obscureConfirm,
                                enabled: !_isLoading,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Re-enter new password',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.4),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.white.withValues(
                                    alpha: 0.05,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.lock_outline,
                                    color: Colors.white54,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirm
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: Colors.white54,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscureConfirm = !_obscureConfirm;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ✅ Bottom Buttons
                Container(
                  padding: const EdgeInsets.only(top: 20),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleChangePassword,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF6B8B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'Change Password',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequirementChip(String label, bool isMet) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isMet
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMet
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.circle_outlined,
            size: 12,
            color: isMet ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isMet ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
