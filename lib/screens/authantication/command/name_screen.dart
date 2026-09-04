import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class NameEntry extends StatefulWidget {
  final void Function(String, String) onNext;
  final PageController controller;
  final VoidCallback onBack;

  const NameEntry({
    super.key,
    required this.onNext,
    required this.controller,
    required this.onBack,
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

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();

    _firstNameController.addListener(_validateFields);
    _lastNameController.addListener(_validateFields);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScreenSize();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  // ✅ API 36: Check screen size for responsive layout
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
    final isDark = context.isDarkMode;
    final backgroundColor = context.backgroundColor;
    final primaryColor = context.primaryColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final errorColor = context.errorColor;

    final double screenWidth = MediaQuery.of(context).size.width;
    final double screenHeight = MediaQuery.of(context).size.height;
    final bool isWeb = screenWidth > 700;
    final double maxWidth = isWeb ? 480 : double.infinity;

    return Scaffold(
      backgroundColor: backgroundColor,
      // ✅ Resize when keyboard opens instead of letting content get squeezed
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: Container(
            width: maxWidth,
            // ✅ Cap the height so the card doesn't force itself onto a
            // constrained parent, but let content scroll inside it.
            constraints: BoxConstraints(
              maxHeight: screenHeight,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color: isWeb
                  ? (isDark
                      ? const Color(0xFF1A1A2E)
                      : const Color(0xFF131C27))
                  : Colors.transparent,
              borderRadius: isWeb
                  ? BorderRadius.circular(16)
                  : null,
              boxShadow: isWeb
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : [],
            ),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                // ✅ FIX: SingleChildScrollView + a min-height constraint
                // means the content scrolls instead of overflowing when
                // the available height is too small (small screens,
                // keyboard open, or web card layout).
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight.isFinite
                              ? constraints.maxHeight
                              : 0,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              /// ⭐ BACK ARROW
                              IconButton(
                                padding: EdgeInsets.zero,
                                alignment: Alignment.centerLeft,
                                icon: Icon(
                                  Icons.arrow_back,
                                  color: textColor,
                                ),
                                onPressed: widget.onBack,
                              ),

                              const SizedBox(height: 10),

                              Text(
                                "What's your name?",
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),

                              const SizedBox(height: 8),

                              Text(
                                "Enter the name you use in real life.",
                                style: TextStyle(
                                  fontSize: 15,
                                  color: secondaryTextColor,
                                ),
                              ),

                              const SizedBox(height: 28),

                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _firstNameController,
                                      style: TextStyle(color: textColor),
                                      decoration: InputDecoration(
                                        hintText: "First name",
                                        hintStyle: TextStyle(
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.grey.shade500,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: _showError &&
                                                    _firstNameController.text
                                                        .trim()
                                                        .isEmpty
                                                ? errorColor
                                                : (isDark
                                                    ? Colors.white24
                                                    : Colors.grey.shade300),
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: _showError &&
                                                    _firstNameController.text
                                                        .trim()
                                                        .isEmpty
                                                ? errorColor
                                                : primaryColor,
                                            width: 1.5,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        errorBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Colors.redAccent,
                                            width: 1.5,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        focusedErrorBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Colors.redAccent,
                                            width: 1.5,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        filled: true,
                                        fillColor: isDark
                                            ? Colors.white.withValues(alpha: 0.05)
                                            : Colors.grey.shade50,
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  Expanded(
                                    child: TextField(
                                      controller: _lastNameController,
                                      style: TextStyle(color: textColor),
                                      decoration: InputDecoration(
                                        hintText: "Last name",
                                        hintStyle: TextStyle(
                                          color: isDark
                                              ? Colors.white54
                                              : Colors.grey.shade500,
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: _showError &&
                                                    _lastNameController.text
                                                        .trim()
                                                        .isEmpty
                                                ? errorColor
                                                : (isDark
                                                    ? Colors.white24
                                                    : Colors.grey.shade300),
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderSide: BorderSide(
                                            color: _showError &&
                                                    _lastNameController.text
                                                        .trim()
                                                        .isEmpty
                                                ? errorColor
                                                : primaryColor,
                                            width: 1.5,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        errorBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Colors.redAccent,
                                            width: 1.5,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        focusedErrorBorder: OutlineInputBorder(
                                          borderSide: const BorderSide(
                                            color: Colors.redAccent,
                                            width: 1.5,
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        filled: true,
                                        fillColor: isDark
                                            ? Colors.white.withValues(alpha: 0.05)
                                            : Colors.grey.shade50,
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              if (_showError) ...[
                                const SizedBox(height: 8),
                                Text(
                                  "Please fill in both first and last name",
                                  style: TextStyle(
                                    color: errorColor,
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
                                    backgroundColor: primaryColor,
                                    disabledBackgroundColor: isDark
                                        ? Colors.white12
                                        : Colors.grey.shade300,
                                    foregroundColor: Colors.white,
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

                              Text(
                                "Your name helps friends find you and ensures your account is secure.",
                                style: TextStyle(
                                  color: secondaryTextColor,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                              ),

                              // Extra breathing room at the bottom when scrolled
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}