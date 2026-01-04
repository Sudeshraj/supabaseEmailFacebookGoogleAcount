import 'package:flutter/material.dart';

class EmailEntry extends StatefulWidget {
  final void Function(String) onNext;
  final PageController controller;

  const EmailEntry({
    super.key,
    required this.onNext,
    required this.controller,
  });

  @override
  State<EmailEntry> createState() => _EmailEntryState();
}

class _EmailEntryState extends State<EmailEntry>
    with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  bool _isValidEmail = false;
  bool _showError = false;

  void _validateEmail(String value) {
    final isValid = RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value);
    setState(() {
      _isValidEmail = isValid;
      _showError = value.isNotEmpty && !isValid;
    });
  }

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    final bool isWeb = screenSize.width > 700;
    final bool isTablet = screenSize.width > 500 && screenSize.width <= 700;

    final double maxWidth = isWeb
        ? 500
        : isTablet
            ? 400
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
                    color:
                        isWeb ? Colors.white.withValues(alpha: 0.03) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: isWeb
                        ? Border.all(color: Colors.white12, width: 1)
                        : null,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 12),
                                  const Text(
                                    "What's your email?",
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    "Enter the email where you can be contacted. No one will see this on your profile.",
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  TextField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    style: const TextStyle(color: Colors.white),
                                    onChanged: _validateEmail,
                                    decoration: InputDecoration(
                                      hintText: "Email",
                                      hintStyle:
                                          const TextStyle(color: Colors.white54),
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
                                          ? "Please enter a valid email address"
                                          : null,
                                      errorStyle: const TextStyle(
                                          color: Colors.redAccent, fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    "You’ll also receive emails from us and can opt out anytime.",
                                    style: TextStyle(
                                        color: Colors.white60, fontSize: 14),
                                  ),
                                  GestureDetector(
                                    onTap: () {},
                                    child: const Text(
                                      "Learn more",
                                      style: TextStyle(
                                          color: Color(0xFF1877F3), fontSize: 14),
                                    ),
                                  ),
                                  const SizedBox(height: 80),
                                ],
                              ),
                            ),
                          ),

                          // 🟩 Fixed Bottom Section (Buttons)
                          Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  onPressed: _isValidEmail
                                      ? () => widget.onNext(_emailController.text)
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
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.white24),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                  ),
                                  onPressed: () {},
                                  child: const Text(
                                    'Sign up with mobile number',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
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
                          )
                        ],
                      );
                    },
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
