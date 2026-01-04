import 'package:flutter/material.dart';

class NetworkBanner extends StatelessWidget {
  final bool offline;

  const NetworkBanner({
    super.key,
    required this.offline,
  });

  @override
  Widget build(BuildContext context) {
    if (!offline) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade700,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: const [
            Icon(Icons.wifi_off, color: Colors.white, size: 20),
            SizedBox(width: 10),
            Text(
              "No Internet Connection",
              style: TextStyle(
                color: Colors.white,
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
