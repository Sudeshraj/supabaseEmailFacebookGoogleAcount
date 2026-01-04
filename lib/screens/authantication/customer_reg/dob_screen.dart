import 'package:flutter/material.dart';

class DobScreen extends StatefulWidget {
  final void Function(DateTime) onNext;
  final PageController controller;

  const DobScreen({
    super.key,
    required this.onNext,
    required this.controller,
  });

  @override
  State<DobScreen> createState() => _DobScreenState();
}

class _DobScreenState extends State<DobScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedMonth;
  String? _selectedDay;
  String? _selectedYear;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  final List<String> _months = const [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  final List<String> _days = List.generate(31, (i) => (i + 1).toString());
  final List<String> _years =
      List.generate(120, (i) => (DateTime.now().year - i).toString());

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
  }

  bool get _isValid =>
      _selectedMonth != null && _selectedDay != null && _selectedYear != null;

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  DateTime get _selectedDate {
    final monthIndex = _months.indexOf(_selectedMonth!) + 1;
    final day = int.parse(_selectedDay!);
    final year = int.parse(_selectedYear!);
    return DateTime(year, monthIndex, day);
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double maxWidth = screenWidth > 700 ? 480 : double.infinity;

    return Scaffold(
      backgroundColor: const Color(0xFF0F1820),

      // ❌ Removed AppBar — Arrow will be inside frame

      body: SafeArea(
        child: Center(
          child: Container(
            width: maxWidth,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              color:
                  screenWidth > 700 ? const Color(0xFF131C27) : Colors.transparent,
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

                    // ⭐ Back Arrow Inside Frame ⭐
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
                      "What's your birthday?",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Choose your date of birth. You can always make this private later.",
                      style: TextStyle(fontSize: 15, color: Colors.white70),
                    ),
                    const SizedBox(height: 28),

                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _buildDropdown(
                            hint: "Month",
                            value: _selectedMonth,
                            items: _months,
                            onChanged: (val) =>
                                setState(() => _selectedMonth = val),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildDropdown(
                            hint: "Day",
                            value: _selectedDay,
                            items: _days,
                            onChanged: (val) =>
                                setState(() => _selectedDay = val),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildDropdown(
                            hint: "Year",
                            value: _selectedYear,
                            items: _years,
                            onChanged: (val) =>
                                setState(() => _selectedYear = val),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),

                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isValid
                            ? () => widget.onNext(_selectedDate)
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isValid
                              ? const Color(0xFF1877F3)
                              : Colors.white12,
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

                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 🔹 Dropdown Builder
  Widget _buildDropdown({
    required String hint,
    required String? value,
    required List<String> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(
          color: Colors.white24,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          dropdownColor: const Color(0xFF1A2633),
          value: value,
          hint: Text(
            hint,
            style: const TextStyle(color: Colors.white70),
          ),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
          items: items
              .map((item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(item,
                        style: const TextStyle(color: Colors.white)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
