import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

Future<void> showNotYouDialog({
  required BuildContext context,
  required String email,
  required String name,
  required String photoUrl,
  required List<String> roles,
  required String buttonText,
  required Future<void> Function() onContinue,
  required Future<void> Function() onNotYou,
}) async {
  if (!context.mounted) return;

  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: "NotYouDialog",
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) {
      return SafeArea(
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: NotYouDialogContent(
              email: email,
              name: name,
              photoUrl: photoUrl,
              roles: roles,
              buttonText: buttonText,
              onContinue: onContinue,
              onNotYou: onNotYou,
            ),
          ),
        ),
      );
    },
    transitionBuilder: (_, animation, _, child) {
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.95, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
          ),
          child: child,
        ),
      );
    },
  );
}

class NotYouDialogContent extends StatefulWidget {
  final String email;
  final String name;
  final String photoUrl;
  final List<String> roles;
  final String buttonText;
  final Future<void> Function() onContinue;
  final Future<void> Function() onNotYou;

  const NotYouDialogContent({
    super.key,
    required this.email,
    required this.name,
    required this.photoUrl,
    required this.roles,
    required this.buttonText,
    required this.onContinue,
    required this.onNotYou,
  });

  @override
  State<NotYouDialogContent> createState() => _NotYouDialogContentState();
}

class _NotYouDialogContentState extends State<NotYouDialogContent> {
  bool _loading = false;

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final isWeb = size.width > 800;

    if (_isTablet != isTablet || _isWeb != isWeb) {
      setState(() {
        _isTablet = isTablet;
        _isWeb = isWeb;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final primaryColor = context.primaryColor;

    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;

    _checkScreenSize();

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: isWeb ? 480 : double.infinity),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          // ✅ AppTheme colors
          color: isDark ? const Color(0xFF0F1820) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.grey.shade200,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ❌ Close button
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  color: textColor,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // 👤 Photo
            CircleAvatar(
              radius: 45,
              backgroundImage:
                  widget.photoUrl.isNotEmpty ? NetworkImage(widget.photoUrl) : null,
              backgroundColor: isDark
                  ? Colors.grey[800]
                  : Colors.grey[200],
              child: widget.photoUrl.isEmpty
                  ? Icon(
                      Icons.person,
                      size: 50,
                      color: isDark ? Colors.white54 : Colors.grey[600],
                    )
                  : null,
            ),
            const SizedBox(height: 16),

            // 📛 Name
            Text(
              widget.name.isNotEmpty ? widget.name : "No Name",
              style: TextStyle(
                fontSize: 22,
                color: textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // 🎫 Roles
            Wrap(
              spacing: 8,
              children: widget.roles.map((role) {
                final roleColor = _getRoleColor(role);
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? roleColor.withValues(alpha: 0.15)
                        : roleColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? roleColor.withValues(alpha: 0.3)
                          : roleColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _getRoleDisplayName(role),
                    style: TextStyle(
                      color: isDark ? Colors.white : roleColor,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ✉ Email
            Text(
              widget.email,
              style: TextStyle(
                color: secondaryTextColor,
              ),
            ),
            const SizedBox(height: 25),

            // 🔵 Continue
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  if (_loading) return;
                  setState(() => _loading = true);
                  await widget.onContinue();
                  if (mounted) setState(() => _loading = false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: _loading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        "Continue",
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 10),

            // 🔴 Not You
            TextButton(
              onPressed: widget.onNotYou,
              child: Text(
                widget.buttonText,
                style: TextStyle(
                  color: isDark ? Colors.redAccent : Colors.red,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ HELPER METHODS
  // ============================================================

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return Colors.blueAccent;
      case 'barber':
        return Colors.orangeAccent;
      case 'customer':
        return Colors.greenAccent;
      default:
        return Colors.grey;
    }
  }

  String _getRoleDisplayName(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return 'Owner';
      case 'barber':
        return 'Barber';
      case 'customer':
        return 'Customer';
      default:
        return role;
    }
  }
}