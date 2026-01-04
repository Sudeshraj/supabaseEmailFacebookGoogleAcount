import 'package:flutter/material.dart';

class ContactScreen extends StatefulWidget {
  final void Function(String email, String mobile) onNext;
  final PageController controller;

  const ContactScreen({
    super.key,
    required this.onNext,
    required this.controller,
  });

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _contactController = TextEditingController();

  String _email = '';
  String _mobile = '';

  bool _isValid = false;
  bool _showError = false;
  bool _showLearnMore = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();
  }

  void _validateContact(String value) {
    final phoneRegex = RegExp(r'^\+?[0-9]{7,15}$');
    final emailRegex = RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$');

    String email = '';
    String mobile = '';
    bool valid = false;

    if (emailRegex.hasMatch(value)) {
      email = value;
      valid = true;
    } else if (phoneRegex.hasMatch(value)) {
      mobile = value;
      valid = true;
    }

    setState(() {
      _email = email;
      _mobile = mobile;
      _isValid = valid;
      _showError = value.isNotEmpty && !valid;
    });
  }

  @override
  void dispose() {
    _contactController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isWeb = screenSize.width > 700;
    final bool isTablet = screenSize.width > 500 && screenSize.width <= 700;

    final double maxWidth = isWeb
        ? 480
        : isTablet
            ? 420
            : double.infinity;

    final EdgeInsets padding = isWeb
        ? const EdgeInsets.symmetric(horizontal: 40, vertical: 30)
        : const EdgeInsets.symmetric(horizontal: 24, vertical: 20);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            widget.controller.previousPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.ease,
            );
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Container(
                  padding: padding,
                  decoration: BoxDecoration(
                    color: isWeb
                        ? Colors.white.withValues(alpha: 0.03)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border:
                        isWeb ? Border.all(color: Colors.white12, width: 1) : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 10),
                      const Text(
                        "What's your mobile number or email?",
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Enter a valid mobile number or email to continue.",
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _contactController,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        onChanged: _validateContact,
                        decoration: InputDecoration(
                          hintText: "Mobile number or Email",
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.transparent,
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _showError
                                  ? Colors.redAccent
                                  : Colors.white24,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: _showError
                                  ? Colors.redAccent
                                  : const Color(0xFF1877F3),
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          errorText: _showError
                              ? "Please enter a valid mobile or email"
                              : null,
                          errorStyle: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "You’ll also receive emails from us and can opt out anytime.",
                        style:
                            TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showLearnMore = !_showLearnMore;
                          });
                        },
                        child: const Text(
                          "Learn more",
                          style: TextStyle(
                            color: Color(0xFF1877F3),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (_showLearnMore) ...[
                        const SizedBox(height: 8),
                        const Text(
                          "We use your contact details to verify your account, send important notifications, and help recover your access securely if needed.",
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isValid
                              ? () => widget.onNext(_email, _mobile)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1877F3),
                            disabledBackgroundColor: Colors.white12,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(25),
                            ),
                          ),
                          child: const Text(
                            'Next',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton(
                          onPressed: () {},
                          child: const Text(
                            "Find my account",
                            style: TextStyle(
                              color: Color(0xFF1877F3),
                              fontSize: 15,
                            ),
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
    );
  }
}
