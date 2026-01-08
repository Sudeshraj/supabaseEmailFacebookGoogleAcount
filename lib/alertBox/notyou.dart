import 'package:flutter/material.dart';

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
    barrierColor: Colors.black.withValues(alpha:0.6),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) {
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
    transitionBuilder: (_, animation, __, child) {
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: isWeb ? 480 : double.infinity),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF0F1820),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ❌ Close button
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            // 👤 Photo
            CircleAvatar(
              radius: 45,
              backgroundImage:
                  widget.photoUrl.isNotEmpty ? NetworkImage(widget.photoUrl) : null,
              child: widget.photoUrl.isEmpty
                  ? const Icon(Icons.person, size: 50, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 16),

            // 📛 Name
            Text(
              widget.name.isNotEmpty ? widget.name : "No Name",
              style: const TextStyle(
                fontSize: 22,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // 🎫 Roles
            Wrap(
              spacing: 8,
              children: widget.roles.map((role) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Text(
                    role,
                    style: const TextStyle(color: Colors.white),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ✉ Email
            Text(
              widget.email,
              style: const TextStyle(color: Colors.grey),
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
                  backgroundColor: const Color(0xFF1877F3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: const Text(
                  "Continue",
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // 🔴 Not You
            TextButton(
              onPressed: widget.onNotYou,
              child: Text(
                widget.buttonText,
                style: const TextStyle(
                  color: Colors.redAccent,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

