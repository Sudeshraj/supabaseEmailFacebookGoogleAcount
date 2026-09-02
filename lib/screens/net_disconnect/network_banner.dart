import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class NetworkBanner extends StatelessWidget {
  final bool offline;

  const NetworkBanner({
    super.key,
    required this.offline,
  });

  @override
  Widget build(BuildContext context) {
    if (!offline) return const SizedBox.shrink();

    final isDark = context.isDarkMode;
    final textColor = context.textColor;
    final errorColor = context.errorColor;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          // ✅ Use error color from theme
          color: isDark 
              ? errorColor.withValues(alpha: 0.85)
              : errorColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.wifi_off,
              color: textColor,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              "No Internet Connection",
              style: TextStyle(
                color: textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}