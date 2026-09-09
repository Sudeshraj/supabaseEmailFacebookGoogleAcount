import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class LoadingOverlay {
  // Previously this used showDialog(), which pushes a Navigator
  // *route*. Popping a route always plays a screen transition -
  // that's what looked like "redirecting" when hide() ran, and it
  // could race with GoRouter and make the error message flash away.
  //
  // An OverlayEntry has nothing to do with the Navigator/route
  // stack at all. Inserting/removing it never triggers a route
  // transition and never interacts with GoRouter, so the screen
  // underneath (including your error message) is untouched - only
  // the spinner itself appears/disappears.
  static OverlayEntry? _entry;

  // Kept for backwards compatibility with existing call sites
  // (e.g. main.dart) - no longer needed for show()/hide() to work.
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
  }

  static void show(BuildContext context, {String message = "Please wait..."}) {
    if (_entry != null) return; // Prevent multiple overlays stacking

    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;

    _entry = OverlayEntry(
      builder: (_) {
        return PopScope(
          canPop: false,
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              color: Colors.black.withValues(alpha: 0.15),
              width: double.infinity,
              height: double.infinity,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E1E1E).withValues(alpha: 0.95)
                        : Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(16),
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
                      CircularProgressIndicator(
                        color: isDark ? primaryColor : Colors.white,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    // rootOverlay: true -> always inserts above everything,
    // including GoRouter's nested navigators, same guarantee
    // useRootNavigator: true gave before.
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  static void hide() {
    if (_entry == null) return;

    try {
      _entry!.remove();
    } catch (_) {
      // Avoid crash if it was already removed some other way
    }

    // Always null this out right after removing - makes hide()
    // idempotent (safe to call twice, e.g. once in an error branch
    // and again in a `finally` block) without ever lying about
    // whether the overlay is actually gone.
    _entry = null;
  }
}