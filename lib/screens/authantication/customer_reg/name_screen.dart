import 'package:flutter/material.dart';

class NameEntry extends StatefulWidget {
  final void Function(String, String) onNext;
  final PageController controller;

  const NameEntry({
    super.key,
    required this.onNext,
    required this.controller,
  });

  @override
  State<NameEntry> createState() => _NameEntryState();
}

class _NameEntryState extends State<NameEntry>
    with SingleTickerProviderStateMixin {
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  bool _showError = false;
  bool _isValid = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation =
        CurvedAnimation(parent: _animationController, curve: Curves.easeIn);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();

    _firstNameController.addListener(_validateFields);
    _lastNameController.addListener(_validateFields);
  }

  void _validateFields() {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();

    final valid = first.isNotEmpty && last.isNotEmpty;

    setState(() {
      _isValid = valid;
      _showError = !valid && (first.isNotEmpty || last.isNotEmpty);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double maxWidth = screenWidth > 700 ? 480 : double.infinity;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),

      body: SafeArea(
        child: Center(
          child: Container(
            width: maxWidth,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: screenWidth > 700
                  ? const Color(0xFF131C27)
                  : Colors.transparent,
              borderRadius:
                  screenWidth > 700 ? BorderRadius.circular(16) : null,
              boxShadow: screenWidth > 700
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : [],
            ),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    /// ⭐ BACK ARROW INSIDE FRAME ⭐
                    IconButton(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        widget.controller.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.ease,
                        );
                      },
                    ),

                    const SizedBox(height: 10),

                    const Text(
                      "What's your name?",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      "Enter the name you use in real life.",
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white70,
                      ),
                    ),

                    const SizedBox(height: 28),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _firstNameController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: "First name",
                              hintStyle: const TextStyle(color: Colors.white54),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: _showError &&
                                          _firstNameController.text
                                              .trim()
                                              .isEmpty
                                      ? Colors.redAccent
                                      : Colors.white24,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: _showError &&
                                          _firstNameController.text
                                              .trim()
                                              .isEmpty
                                      ? Colors.redAccent
                                      : const Color(0xFF1877F3),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 12),

                        Expanded(
                          child: TextField(
                            controller: _lastNameController,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: "Last name",
                              hintStyle: const TextStyle(color: Colors.white54),
                              enabledBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: _showError &&
                                          _lastNameController.text
                                              .trim()
                                              .isEmpty
                                      ? Colors.redAccent
                                      : Colors.white24,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderSide: BorderSide(
                                  color: _showError &&
                                          _lastNameController.text
                                              .trim()
                                              .isEmpty
                                      ? Colors.redAccent
                                      : const Color(0xFF1877F3),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (_showError) ...[
                      const SizedBox(height: 8),
                      const Text(
                        "Please fill in both first and last name",
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 13,
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isValid
                            ? () => widget.onNext(
                                  _firstNameController.text.trim(),
                                  _lastNameController.text.trim(),
                                )
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

                    const SizedBox(height: 28),

                    const Text(
                      "Your name helps friends find you and ensures your account is secure.",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
