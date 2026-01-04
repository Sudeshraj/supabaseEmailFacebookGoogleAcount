import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/screens/authantication/command/multi_continue_screen.dart';
import 'package:flutter_application_1/screens/authantication/command/registration_flow.dart';
import 'package:flutter_application_1/screens/authantication/command/sign_in.dart';
import 'package:flutter_application_1/screens/authantication/command/splash.dart';

class NotYouScreen extends StatefulWidget {
  final String email;
  final String name;
  final String photoUrl;
  final List<String> roles;
  final String buttonText;
  final Future<void> Function() onNotYou;
  final Future<void> Function() onContinue;
  final String page;

  const NotYouScreen({
    super.key,
    required this.email,
    required this.name,
    required this.photoUrl,
    required this.roles,
    required this.buttonText,
    required this.onNotYou,
    required this.onContinue,
    required this.page,
  });

  @override
  State<NotYouScreen> createState() => _NotYouScreenState();
}

class _NotYouScreenState extends State<NotYouScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  late final Animation<double> _scale = Tween(
    begin: 0.95,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBackNavigation() {
    Widget target;
    FirebaseAuth.instance.signOut();
    switch (widget.page) {    
      case 'signup':
        target = const RegistrationFlow();
        break;
      case 'cont':
        target = const ContinueScreen();
        break;
      case 'splash':
        target = const SplashScreen();
        break;
      default:
        target = const SignInScreen();
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => target),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;

    return PopScope(
      canPop: false, // 🚫 Prevent browser & hardware back navigation
      onPopInvokedWithResult: (didPop, result) {
        // Optional debug/logging callback
        debugPrint("Back navigation prevented on NotYouScreen");
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F1820),
        body: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWeb ? 480 : double.infinity,
                  ),
                  child: Container(
                    height: size.height - 40,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 20,
                    ),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: [
                        // 🔙 Back arrow (manual navigation)
                        Align(
                          alignment: Alignment.topLeft,
                          child: IconButton(
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                            onPressed: _handleBackNavigation,
                          ),
                        ),
                        const SizedBox(height: 10),

                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              children: [
                                // 👤 Profile Photo
                                CircleAvatar(
                                  radius: 45,
                                  backgroundImage: widget.photoUrl.isNotEmpty
                                      ? NetworkImage(widget.photoUrl)
                                      : null,
                                  child: widget.photoUrl.isEmpty
                                      ? const Icon(
                                          Icons.person,
                                          size: 50,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 16),

                                // 📛 Name
                                Text(
                                  widget.name.isNotEmpty
                                      ? widget.name
                                      : "No Name",
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
                                  runSpacing: 8,
                                  children: widget.roles.map((role) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 6,
                                        horizontal: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.08,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: Colors.white24,
                                        ),
                                      ),
                                      child: Text(
                                        role,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 20),

                                // ✉ Email
                                Text(
                                  widget.email,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 25),

                                // 🔵 Continue Button
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      if (_loading) return;
                                      setState(() => _loading = true);
                                      await widget.onContinue();
                                      if (mounted) {
                                        setState(() => _loading = false);
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1877F3),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                    ),
                                    child: const Text(
                                      "Continue",
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                // 🔴 Not You Button
                                TextButton(
                                  onPressed: widget.onNotYou,
                                  child: Text(
                                    widget.buttonText.isNotEmpty
                                        ? widget.buttonText
                                        : "",
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 16,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
