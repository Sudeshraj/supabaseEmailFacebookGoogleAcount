import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

Future<void> showResetPasswordDialog(BuildContext context) async {
  final emailController = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool isValidEmail = false;

  await showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Reset Password',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (context, anim, _, __) {
      final size = MediaQuery.of(context).size;
      final isWeb = size.width > 600;

      return Center(
        child: FractionallySizedBox(
          widthFactor: isWeb ? 0.4 : 0.9,
          child: Transform.scale(
            scale: Curves.easeOutBack.transform(anim.value),
            child: Opacity(
              opacity: anim.value,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return Dialog(
                    backgroundColor: const Color(0xFF121A24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    insetPadding: const EdgeInsets.all(24),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 24,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Reset your password',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Enter your registered email to receive a reset link.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 20),

                              /// 📧 Email Field
                              Form(
                                key: formKey,
                                child: TextFormField(
                                  controller: emailController,
                                  style: const TextStyle(color: Colors.white),
                                  cursorColor: const Color(0xFF1877F3),
                                  decoration: InputDecoration(
                                    hintText: 'Enter your email',
                                    hintStyle: const TextStyle(
                                      color: Colors.white38,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white.withValues(
                                      alpha: 0.05,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 12,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: const BorderSide(
                                        color: Colors.white24,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                        color: isValidEmail
                                            ? const Color(0xFF1877F3)
                                            : Colors.redAccent,
                                      ),
                                    ),
                                    suffixIcon: isValidEmail
                                        ? const Icon(
                                            Icons.check_circle,
                                            color: Color(0xFF4CAF50),
                                          )
                                        : const Icon(
                                            Icons.error_outline,
                                            color: Colors.redAccent,
                                          ),
                                  ),
                                  onChanged: (value) {
                                    final emailRegex = RegExp(
                                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                    );
                                    setState(() {
                                      isValidEmail = emailRegex.hasMatch(
                                        value.trim(),
                                      );
                                    });
                                  },
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your email';
                                    }
                                    final emailRegex = RegExp(
                                      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                    );
                                    if (!emailRegex.hasMatch(value.trim())) {
                                      return 'Enter a valid email';
                                    }
                                    return null;
                                  },
                                ),
                              ),

                              const SizedBox(height: 24),

                              /// 📤 Submit Button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: isValidEmail
                                      ? () async {
                                          if (!formKey.currentState!
                                              .validate()) {
                                            return;
                                          }

                                          try {
                                            await FirebaseAuth.instance
                                                .sendPasswordResetEmail(
                                                  email: emailController.text
                                                      .trim(),
                                                );

                                            if (!context.mounted) return;

                                            Navigator.of(context).pop();

                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Password reset link sent!',
                                                ),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          } catch (e) {
                                            if (!context.mounted) return;

                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Error: ${e.toString()}',
                                                ),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        }
                                      : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isValidEmail
                                        ? const Color(0xFF1877F3)
                                        : Colors.grey,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text(
                                    'Send Reset Link',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        /// ❌ Close Button
                        Positioned(
                          right: -6,
                          top: -6,
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.9),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}
