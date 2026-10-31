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
///
/// ✅ How deletion works end to end:
///   1. This screen only SCHEDULES deletion (90-day grace period).
///   2. Logging in again within 90 days restores the account.
///   3. After 90 days the server does everything on its own:
///        01:45 UTC  revoke-apple-tokens (Edge Function, Apple users)
///        02:00 UTC  process_expired_profile_deletions() (pg_cron)
///      -> deletes the data, the profile AND the auth.users login.
///   The app must NOT call revoke-apple-tokens itself: that function is
///   cron-only (it needs the CRON_SECRET), and Apple's token must stay
///   valid during the grace period so a restore keeps working.
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
  }

  void _validateConfirmText() {
    final isValid =
        _confirmController.text.trim().toUpperCase() == _confirmKeyword;
    if (isValid != _confirmTextValid) {
      setState(() => _confirmTextValid = isValid);
    }
  }

  // ✅ Back works whether the screen was pushed (context.push) or opened
  // with context.go (nothing to pop).
  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
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

      // Step 1: Schedule profile-level deletion (90-day grace period).
      // Must run BEFORE logout (the database function checks auth.uid()).
      final success = await SessionManager.updateProfileLevelStatus(
        email: _userEmail!,
        status: 'scheduled_for_deletion',
        gracePeriodDays: 90,
      );

      if (!success) {
        throw Exception('Failed to schedule account deletion');
      }

      debugPrint('✅ Account scheduled for deletion');

      // Step 2: Tell the user FIRST, while this screen still exists.
      // (After logout the router replaces this screen, which would
      // remove the dialog and `mounted` would already be false.)
      if (!mounted) return;
      setState(() => _isLoading = false);

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: dialogContext.backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Account Deletion Scheduled',
                  style: dialogContext.titleLarge.copyWith(
                    color: dialogContext.textColor,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Your account has been deactivated and is scheduled for '
            'permanent deletion in 90 days.\n\n'
            'You can restore your account anytime within this period '
            'by logging back in.',
            style: dialogContext.bodyMedium.copyWith(
              color: dialogContext.textColor,
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // Step 3: Full logout. appState.logout() clears the state in one
      // go and the router sends the user to /continue or /login itself,
      // so no context.go() is needed here.
      try {
        await appState.logout();
      } catch (e) {
        debugPrint('⚠️ Logout after scheduling failed: $e');
        await Supabase.instance.client.auth.signOut();
      }
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
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _goBack,
          tooltip: 'Back',
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : SafeArea(child: isWeb ? _buildWebLayout() : _buildMobileLayout()),
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
            border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
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
                '• Salons you own will be deactivated; upcoming appointments will be cancelled\n'
                '• Paid subscriptions are not cancelled automatically - cancel them in Google Play / the App Store\n'
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
            border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
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
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
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
            onPressed: _confirmTextValid ? _confirmAndDeleteAccount : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              disabledBackgroundColor: isDark
                  ? Colors.grey[800]
                  : Colors.grey[300],
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Delete My Account',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _goBack,
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
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
          ),
        ),
      ],
    );
  }
}
