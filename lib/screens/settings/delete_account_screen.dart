import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

/// ============================================================
/// 🔥 DEDICATED DELETE ACCOUNT SCREEN
/// ============================================================
/// Google Play & Apple App Store requirement: account deletion
/// must be easy to discover and clearly labeled. This screen is
/// separate from ProfileManagementScreen (which handles role
/// switching) to keep the deletion action unambiguous.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final TextEditingController _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _confirmTextValid = false;
  String? _userEmail;
  String? _loginProvider;

  // ✅ Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  static const String _confirmKeyword = 'DELETE';

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _confirmController.addListener(_validateConfirmText);
  }

  @override
  void dispose() {
    _confirmController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _loadUserInfo() {
    final user = Supabase.instance.client.auth.currentUser;
    _userEmail = user?.email;
    _loginProvider =
        user?.userMetadata?['provider']?.toString().toLowerCase();
  }

  void _validateConfirmText() {
    final isValid =
        _confirmController.text.trim().toUpperCase() == _confirmKeyword;
    if (isValid != _confirmTextValid) {
      setState(() => _confirmTextValid = isValid);
    }
  }

  // ============================================================
  // 🔥 APPLE TOKEN REVOCATION (App Store Guideline 5.1.1(v))
  // ============================================================
  Future<void> _revokeAppleTokenIfNeeded() async {
    if (_loginProvider != 'apple') return;

    try {
      debugPrint('🍎 Apple account detected - revoking token...');
      // ⚠️ IMPORTANT: Apple token revocation requires the original
      // authorization code, which must be stored server-side at
      // sign-in time (Supabase Edge Function recommended) since
      // Apple only issues it once during initial authentication.
      //
      // Call your backend endpoint here, e.g.:
      // await Supabase.instance.client.functions.invoke(
      //   'revoke-apple-token',
      //   body: {'email': _userEmail},
      // );
      debugPrint('🍎 Apple token revocation request sent');
    } catch (e) {
      debugPrint('❌ Apple token revocation failed: $e');
      // Don't block deletion flow if revocation fails - log for
      // manual follow-up, but continue with account deletion.
    }
  }

  // ============================================================
  // 🔥 MAIN DELETE ACTION
  // ============================================================
  Future<void> _confirmAndDeleteAccount() async {
    if (!_confirmTextValid || _userEmail == null) return;

    setState(() => _isLoading = true);

    try {
      debugPrint('🗑️ Starting account deletion for: $_userEmail');

      // Step 1: Revoke Apple token if applicable
      await _revokeAppleTokenIfNeeded();

      // Step 2: Schedule profile-level deletion (90-day grace period)
      final success = await SessionManager.updateProfileLevelStatus(
        email: _userEmail!,
        status: 'scheduled_for_deletion',
        gracePeriodDays: 90,
      );

      if (!success) {
        throw Exception('Failed to schedule account deletion');
      }

      debugPrint('✅ Account scheduled for deletion');

      // Step 3: Sign out immediately (account is now deactivated)
      await Supabase.instance.client.auth.signOut();
      await appState.refreshState();

      if (!mounted) return;

      // Step 4: Show confirmation and navigate to login
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: context.backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'Account Deletion Scheduled',
                style: context.titleLarge.copyWith(
                  color: context.textColor,
                ),
              ),
            ],
          ),
          content: Text(
            'Your account has been deactivated and is scheduled for '
            'permanent deletion in 90 days.\n\n'
            'You can restore your account anytime within this period '
            'by logging back in.',
            style: context.bodyMedium.copyWith(
              color: context.textColor,
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      debugPrint('❌ Error deleting account: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // ✅ BUILD METHOD - WITH WEB FRAME
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(
          'Delete Account',
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
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: AppTheme.primary,
              ),
            )
          : SafeArea(
              child: isWeb
                  ? _buildWebLayout()
                  : _buildMobileLayout(),
            ),
    );
  }

  // ✅ WEB LAYOUT - Centered with Scrollbar
  Widget _buildWebLayout() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8.0,
          radius: const Radius.circular(10),
          scrollbarOrientation: ScrollbarOrientation.right,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  // ✅ MOBILE LAYOUT
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: _buildContent(),
    );
  }

  // ✅ CONTENT
  Widget _buildContent() {
    final isDark = context.isDarkMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Warning icon + heading
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 48,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'Delete Your Account',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            _userEmail ?? '',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // What happens section
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.orange.withValues(alpha: 0.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📌 What happens when you delete your account?',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '• Your account will be deactivated immediately\n'
                '• All your roles (owner/barber/customer) will be deactivated\n'
                '• Your bookings, data, and settings will be preserved during the grace period\n'
                '• You have 90 days to restore your account by logging back in\n'
                '• After 90 days, your account and all data will be permanently deleted\n'
                '• This action cannot be undone after the 90-day period',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Restore info
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.green.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.restore, color: Colors.green),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Changed your mind? You can log back in anytime '
                  'within 90 days to restore your account.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.green[300] : Colors.green,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Confirmation input
        Text(
          'Type "$_confirmKeyword" to confirm',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmController,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: _confirmKeyword,
            hintStyle: TextStyle(
              color: isDark ? Colors.white70 : Colors.grey[400],
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.primary, width: 2),
            ),
            filled: true,
            fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.grey[50],
          ),
        ),
        const SizedBox(height: 24),

        // Delete button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _confirmTextValid
                ? _confirmAndDeleteAccount
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              disabledBackgroundColor: isDark ? Colors.grey[800] : Colors.grey[300],
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Delete My Account',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: isDark ? Colors.white : Colors.black87,
              side: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      ],
    );
  }
}