// meka auth setting screen eken call venne email&password account ekak thiyenavanam vitarak
import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/auth_provider_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

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
    final isDark = context.isDarkMode;
    final screenSize = MediaQuery.of(context).size;
    final isWeb = screenSize.width > 700;
    final maxWidth = isWeb ? 480.0 : double.infinity;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFF0F1820),
      appBar: AppBar(
        title: Text(
          'Change Password',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
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
            padding: EdgeInsets.all(isWeb ? 32 : 20),
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ✅ Header
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark 
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDark 
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.lock_outline,
                                  color: AppTheme.primary,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Change Password',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Password must be at least 6 characters',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark 
                                            ? Colors.white.withValues(alpha: 0.6)
                                            : Colors.white.withValues(alpha: 0.7),
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
                            color: isDark 
                                ? Colors.white.withValues(alpha: 0.03)
                                : Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark 
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Current Password',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white60 : Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _currentPasswordController,
                                obscureText: _obscureCurrent,
                                enabled: !_isLoading,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.white,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Enter current password',
                                  hintStyle: TextStyle(
                                    color: isDark 
                                        ? Colors.white.withValues(alpha: 0.3)
                                        : Colors.white.withValues(alpha: 0.4),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: isDark 
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.white.withValues(alpha: 0.05),
                                  prefixIcon: Icon(
                                    Icons.lock_outline,
                                    color: isDark ? Colors.white54 : Colors.white54,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureCurrent
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: isDark ? Colors.white54 : Colors.white54,
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
                            color: isDark 
                                ? Colors.white.withValues(alpha: 0.03)
                                : Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark 
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'New Password',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white60 : Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _newPasswordController,
                                obscureText: _obscureNew,
                                enabled: !_isLoading,
                                onChanged: _validatePassword,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.white,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Enter new password',
                                  hintStyle: TextStyle(
                                    color: isDark 
                                        ? Colors.white.withValues(alpha: 0.3)
                                        : Colors.white.withValues(alpha: 0.4),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: isDark 
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.white.withValues(alpha: 0.05),
                                  prefixIcon: Icon(
                                    Icons.lock_outline,
                                    color: isDark ? Colors.white54 : Colors.white54,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureNew
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: isDark ? Colors.white54 : Colors.white54,
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
                              color: isDark 
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : Colors.white.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark 
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.white.withValues(alpha: 0.08),
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
                                        color: isDark 
                                            ? Colors.white.withValues(alpha: 0.5)
                                            : Colors.white.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: _getPasswordStrength(),
                                          backgroundColor: isDark 
                                              ? Colors.white.withValues(alpha: 0.08)
                                              : Colors.white.withValues(alpha: 0.1),
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
                            color: isDark 
                                ? Colors.white.withValues(alpha: 0.03)
                                : Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark 
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Confirm New Password',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white60 : Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _confirmPasswordController,
                                obscureText: _obscureConfirm,
                                enabled: !_isLoading,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.white,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Re-enter new password',
                                  hintStyle: TextStyle(
                                    color: isDark 
                                        ? Colors.white.withValues(alpha: 0.3)
                                        : Colors.white.withValues(alpha: 0.4),
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: isDark 
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.white.withValues(alpha: 0.05),
                                  prefixIcon: Icon(
                                    Icons.lock_outline,
                                    color: isDark ? Colors.white54 : Colors.white54,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscureConfirm
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                      color: isDark ? Colors.white54 : Colors.white54,
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
                            backgroundColor: AppTheme.primary,
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
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.white54,
                            fontSize: 14,
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
      ),
    );
  }

  Widget _buildRequirementChip(String label, bool isMet) {
    final isDark = context.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isMet
            ? Colors.green.withValues(alpha: 0.1)
            : isDark 
                ? Colors.grey.withValues(alpha: 0.15)
                : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMet
              ? Colors.green.withValues(alpha: 0.3)
              : isDark 
                  ? Colors.grey.withValues(alpha: 0.3)
                  : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.circle_outlined,
            size: 12,
            color: isMet ? Colors.green : (isDark ? Colors.grey[600] : Colors.grey),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isMet 
                  ? Colors.green 
                  : (isDark ? Colors.grey[500] : Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}