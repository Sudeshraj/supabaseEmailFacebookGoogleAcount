import 'package:flutter/material.dart';

class GenderSelection extends StatefulWidget {
  final void Function(String) onNext;
  final PageController controller;

  const GenderSelection({
    super.key,
    required this.onNext,
    required this.controller,
  });

  @override
  State<GenderSelection> createState() => _GenderSelectionState();
}

class _GenderSelectionState extends State<GenderSelection>
    with SingleTickerProviderStateMixin {
  String? _selectedGender;
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

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutBack),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // ---------------- Custom "radio" option (no Radio / no deprecation) ----------------
  Widget _buildGenderOption(String title, {String? subtitle}) {
    final bool selected = _selectedGender == title;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(
          color: selected ? const Color(0xFF1877F3) : Colors.white24,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          setState(() {
            _selectedGender = title;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              child: Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                // keep the icon visible on dark background
                color: selected ? const Color(0xFF1877F3) : Colors.white70,
                size: 22,
              ),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: subtitle != null
                ? Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  )
                : null,
          ),
        ),
      ),
    );
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
                      ),
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
                    // Back button
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
                      "What's your gender?",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 8),

                    const Text(
                      "You can change who sees your gender on your profile later.",
                      style: TextStyle(fontSize: 15, color: Colors.white70),
                    ),

                    const SizedBox(height: 28),

                    // Use custom option widgets
                    _buildGenderOption('Female'),
                    _buildGenderOption('Male'),
                    _buildGenderOption(
                      'More options',
                      subtitle:
                          "Select More options to choose another gender or if you'd rather not say.",
                    ),

                    if (_selectedGender == null)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          "Please select your gender",
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 14,
                          ),
                        ),
                      ),

                    const SizedBox(height: 26),

                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _selectedGender != null
                            ? () => widget.onNext(_selectedGender!)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _selectedGender != null
                              ? const Color(0xFF1877F3)
                              : Colors.white12,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: const Text(
                          "Next",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 90),
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
