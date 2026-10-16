import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/main.dart' show appState;

/// Shown at `/account-restore-pending` while the signed-in user's account is
/// either scheduled for deletion or deactivated.
///
/// This REPLACES the old `_PendingRestoreScreen` (spinner only) AND the
/// old `_showRestoreDialog()` / `_showReactivateDialog()` dialogs.
///
/// Why a screen instead of a dialog: a dialog is a "pageless" route. When the
/// page under it is replaced (SignInScreen -> this screen via `context.go`),
/// Flutter's Navigator removes the dialog too, so it flashed and vanished.
/// A page-based screen can't be removed that way.
class PendingRestoreScreen extends StatefulWidget {
  const PendingRestoreScreen({super.key});

  @override
  State<PendingRestoreScreen> createState() => _PendingRestoreScreenState();
}

class _PendingRestoreScreenState extends State<PendingRestoreScreen> {
  bool _busy = false;

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (appState.pendingDeletionRestore) {
        await appState.confirmRestoreScheduledProfile();
      } else if (appState.pendingReactivation) {
        await appState.confirmReactivateProfile();
      }
      // On success the pending flag clears, notifyListeners() fires and the
      // GoRouter redirect moves us away from this route automatically.
    } catch (e) {
      debugPrint('❌ Restore/reactivate failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    // If it failed, appState.errorMessage holds the reason.
    final err = appState.errorMessage;
    if (mounted && err != null && err.isNotEmpty && _stillPending) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (appState.pendingDeletionRestore) {
        await appState.declineRestoreAndLogout();
      } else {
        await appState.declineReactivationAndLogout();
      }
    } catch (e) {
      debugPrint('❌ Logout from restore screen failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _stillPending =>
      appState.pendingDeletionRestore || appState.pendingReactivation;

  @override
  Widget build(BuildContext context) {
    final primary = context.primaryColor;
    final textColor = context.textColor;
    final secondary = context.secondaryTextColor;

    return PopScope(
      canPop: false, // user must choose Restore or Log Out
      child: Scaffold(
        backgroundColor: context.backgroundColor,
        body: SafeArea(
          child: Center(
            child: ListenableBuilder(
              listenable: appState,
              builder: (context, _) {
                final isDeletion = appState.pendingDeletionRestore;
                final isReactivation = appState.pendingReactivation;
                final days = appState.deletionRestoreDaysRemaining;

                // Nothing pending (e.g. redirect about to move us away).
                if (!isDeletion && !isReactivation) {
                  return CircularProgressIndicator(color: primary);
                }

                final title = isDeletion
                    ? 'Restore Your Account?'
                    : 'Reactivate Your Account?';

                final message = isDeletion
                    ? (days != null
                          ? 'Your account is scheduled for deletion in $days '
                                'days. Would you like to restore it and '
                                'continue using the app, or log out and let '
                                'the deletion proceed?'
                          : 'Your account is scheduled for deletion. Would '
                                'you like to restore it and continue using '
                                'the app, or log out and let the deletion '
                                'proceed?')
                    : 'Your account is currently deactivated. Would you like '
                          'to reactivate it and continue using the app, or '
                          'log out and keep it deactivated?';

                final restoreLabel = isDeletion
                    ? 'Restore My Account'
                    : 'Reactivate My Account';

                return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.restore, size: 56, color: primary),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: secondary, height: 1.4),
                        ),
                        const SizedBox(height: 28),
                        if (_busy)
                          CircularProgressIndicator(color: primary)
                        else ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _restore,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primary,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(restoreLabel),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _logout,
                            style: TextButton.styleFrom(
                              foregroundColor: secondary,
                            ),
                            child: const Text('Log Out'),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}