// utils/simple_toast.dart
import 'package:flutter/material.dart';

class SimpleToast {
  static void show({
    required BuildContext context,
    required String message,
    Duration duration = const Duration(seconds: 3),
    Color backgroundColor = Colors.black87,
    double borderRadius = 8.0,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 16.0,
      vertical: 12.0,
    ),
    TextStyle textStyle = const TextStyle(color: Colors.white, fontSize: 14.0),
  }) {
    // Remove any existing toast first
    _removeExistingToast(context);

    // Create and show new toast
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: MediaQuery.of(context).viewInsets.bottom + 50,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: () => _removeExistingToast(context),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  message,
                  style: textStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Store reference
    _currentEntry = overlayEntry;

    // Insert overlay
    overlay.insert(overlayEntry);

    // Auto remove after duration
    Future.delayed(duration, () {
      _removeExistingToast(context);
    });
  }

  static OverlayEntry? _currentEntry;

  static void _removeExistingToast(BuildContext context) {
    if (_currentEntry != null && _currentEntry!.mounted) {
      _currentEntry!.remove();
      _currentEntry = null;
    }
  }

  // ✅ Fix helper methods
  static void info(BuildContext context, String message, {Duration? duration}) {
    show(
      context: context,
      message: message,
      backgroundColor: Colors.blue,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  static void success(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    show(
      context: context,
      message: message,
      backgroundColor: Colors.green,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    show(
      context: context,
      message: message,
      backgroundColor: Colors.red,
      duration: duration ?? const Duration(seconds: 5),
    );
  }

  static void warning(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    show(
      context: context,
      message: message,
      backgroundColor: Colors.orange,
      duration: duration ?? const Duration(seconds: 4),
    );
  }
}
