import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class LoadingOverlay {
  static bool _isDialogOpen = false;

  // Global navigatorKey (root navigator)
  static GlobalKey<NavigatorState>? _navKey;

  // Set from main.dart
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navKey = key;
  }

  // -------------------------------------------------------------
  // SHOW LOADING
  // -------------------------------------------------------------
  static void show(BuildContext context, {String message = "Please wait..."}) {
    if (_isDialogOpen) return; // Prevent multiple dialogs
    _isDialogOpen = true;

    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true, // Important for global pop
      builder: (_) {
        return PopScope(
          canPop: false, // Prevent back button from closing
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.symmetric(horizontal: 40),
                decoration: BoxDecoration(
                  // ✅ Theme aware background
                  color: isDark
                      ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                      : Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                  // ✅ Subtle border for dark mode
                  border: isDark
                      ? Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                          width: 1,
                        )
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ✅ Primary color for progress indicator
                    CircularProgressIndicator(
                      color: isDark ? primaryColor : Colors.white,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        // ✅ Theme aware text color
                        color: isDark ? Colors.white : Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------
  // HIDE LOADING
  // -------------------------------------------------------------
  static void hide() {
    if (!_isDialogOpen) return;

    try {
      // Pop using global root navigator
      final nav = _navKey?.currentState;

      if (nav != null && nav.canPop()) {
        nav.pop();
      } else if (_navKey?.currentContext != null) {
        Navigator.of(_navKey!.currentContext!, rootNavigator: true).pop();
      }
    } catch (_) {
      // Avoid crash
    }

    _isDialogOpen = false;
  }
}