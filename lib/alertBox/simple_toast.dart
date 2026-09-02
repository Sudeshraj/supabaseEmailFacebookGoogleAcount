// utils/simple_toast.dart
import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class SimpleToast {
  static void show({
    required BuildContext context,
    required String message,
    Duration duration = const Duration(seconds: 3),
    Color? backgroundColor,
    double borderRadius = 8.0,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
      horizontal: 16.0,
      vertical: 12.0,
    ),
    TextStyle? textStyle,
  }) {
    // ✅ Theme based colors
    final isDark = context.isDarkMode;
    final bgColor = backgroundColor ?? (isDark ? Colors.grey[800] : Colors.black87);
    final textColor = isDark ? Colors.white : Colors.white;
    final textStyleToUse = textStyle ?? TextStyle(
      color: textColor,
      fontSize: 14.0,
    );

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
                color: bgColor,
                borderRadius: BorderRadius.circular(borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  message,
                  style: textStyleToUse,
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
      if (context.mounted) {
        _removeExistingToast(context);
      }
    });
  }

  static OverlayEntry? _currentEntry;

  static void _removeExistingToast(BuildContext context) {
    if (_currentEntry != null && _currentEntry!.mounted) {
      _currentEntry!.remove();
      _currentEntry = null;
    }
  }

  // ✅ Info Toast - Theme aware
  static void info(BuildContext context, String message, {Duration? duration}) {
    final isDark = context.isDarkMode;
    show(
      context: context,
      message: message,
      backgroundColor: isDark ? Colors.blue[700] : Colors.blue,
      duration: duration ?? const Duration(seconds: 4),
    );
  }

  // ✅ Success Toast - Theme aware
  static void success(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    final isDark = context.isDarkMode;
    show(
      context: context,
      message: message,
      backgroundColor: isDark ? Colors.green[700] : Colors.green,
      duration: duration ?? const Duration(seconds: 3),
    );
  }

  // ✅ Error Toast - Theme aware
  static void error(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    final isDark = context.isDarkMode;
    show(
      context: context,
      message: message,
      backgroundColor: isDark ? Colors.red[700] : Colors.red,
      duration: duration ?? const Duration(seconds: 5),
    );
  }

  // ✅ Warning Toast - Theme aware
  static void warning(
    BuildContext context,
    String message, {
    Duration? duration,
  }) {
    final isDark = context.isDarkMode;
    show(
      context: context,
      message: message,
      backgroundColor: isDark ? Colors.orange[700] : Colors.orange,
      duration: duration ?? const Duration(seconds: 4),
    );
  }
}