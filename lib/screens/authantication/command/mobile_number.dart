import 'dart:ui';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_libphonenumber/flutter_libphonenumber.dart'
    as flutter_lib;

class MobileNumberScreen extends StatefulWidget {
  final void Function(String e164) onNext;
  final PageController controller;

  const MobileNumberScreen({
    super.key,
    required this.onNext,
    required this.controller,
  });

  @override
  State<MobileNumberScreen> createState() => MobileNumberScreenState();
}

class MobileNumberScreenState extends State<MobileNumberScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _mobileController = TextEditingController();
  String? _mobileError;
  bool _isValid = false;

  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<double> _scale;

  late Country selectedCountry;
  bool _libInit = false;

  @override
  void initState() {
    super.initState();

    selectedCountry = Country(
      phoneCode: "94",
      countryCode: "LK",
      name: "Sri Lanka",
      displayName: "Sri Lanka",
      displayNameNoCountryCode: "Sri Lanka",
      example: "712345678",
      e164Sc: 0,
      geographic: true,
      level: 1,
      e164Key: "",
    );

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );

    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _scale = Tween(begin: 0.95, end: 1.0)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _controller.forward();

    _mobileController.addListener(_validateMobile);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLib();
      _autoDetectCountry();
    });
  }

  Future<void> _initLib() async {
    try {
      await flutter_lib.init();
      _libInit = true;
    } catch (_) {
      _libInit = false;
    }
  }

  Future<void> _autoDetectCountry() async {
    try {
      final locale = View.of(context).platformDispatcher.locale;
      final code = locale.countryCode;

      if (code == null) return;

      Country? parsed;

      try {
        parsed = CountryParser.parseCountryCode(code);
      } catch (_) {}

      if (parsed == null) {
        try {
          parsed = CountryParser.parseCountryCode(code.toUpperCase());
        } catch (_) {}
      }

      if (parsed == null) {
        try {
          parsed = CountryParser.parseCountryCode(code.toLowerCase());
        } catch (_) {}
      }

      if (parsed == null) {
        if (code.toUpperCase() == "US") {
          parsed = Country(
            phoneCode: "1",
            countryCode: "US",
            name: "United States",
            displayName: "United States",
            displayNameNoCountryCode: "United States",
            example: "2015550123",
            e164Sc: 0,
            geographic: true,
            level: 1,
            e164Key: "",
          );
        } else if (code.toUpperCase() == "LK") {
          parsed = Country(
            phoneCode: "94",
            countryCode: "LK",
            name: "Sri Lanka",
            displayName: "Sri Lanka",
            displayNameNoCountryCode: "Sri Lanka",
            example: "712345678",
            geographic: true,
            level: 1,
            e164Key: "",
            e164Sc: 0,
          );
        }
      }

      if (!mounted) return;

      if (parsed != null) {
        setState(() => selectedCountry = parsed!);
      }
    } catch (_) {}
  }

  bool _validateSriLanka(String n) {
    n = n.trim();
    if (n.startsWith("0")) {
      return RegExp(r"^0[0-9]{9}$").hasMatch(n);
    }
    return RegExp(r"^[0-9]{9}$").hasMatch(n);
  }

  Future<bool> _validateUsingLib(String number) async {
    if (!_libInit) return false;

    try {
      final result = await flutter_lib.parse(
        number,
        region: selectedCountry.countryCode,
      );
      return result["e164"] != null;
    } catch (_) {
      return false;
    }
  }

  void _validateMobile() async {
    String number = _mobileController.text.trim();

    if (number.isEmpty) {
      setState(() {
        _mobileError = "Enter your mobile number";
        _isValid = false;
      });
      return;
    }

    bool valid = false;
    String? error;

    if (selectedCountry.countryCode == "LK") {
      valid = _validateSriLanka(number);
      if (!valid) error = "Invalid Sri Lanka number";
    } else {
      valid = await _validateUsingLib(number);
      if (!valid) error = "Invalid mobile number";
    }

    if (!mounted) return;

    setState(() {
      _mobileError = error;
      _isValid = valid && error == null;
    });
  }

  Future<String?> _formatE164(String number) async {
    number = number.trim();

    if (selectedCountry.countryCode == "LK" && number.startsWith("0")) {
      number = number.substring(1);
    }

    if (!_libInit) {
      return "+${selectedCountry.phoneCode}$number";
    }

    try {
      final parsed = await flutter_lib.parse(
        number,
        region: selectedCountry.countryCode,
      );
      return parsed["e164"] as String?;
    } catch (_) {
      return "+${selectedCountry.phoneCode}$number";
    }
  }

  void _showPicker() {
    showCountryPicker(
      context: context,
      showPhoneCode: true,
      onSelect: (c) {
        setState(() => selectedCountry = c);
        _validateMobile();
      },
    );
  }

  Future<void> _onNext() async {
    if (!_isValid) {
      _validateMobile();
      return;
    }

    final e164 = await _formatE164(_mobileController.text.trim());
    if (e164 != null) widget.onNext(e164);
  }

  @override
  void dispose() {
    _controller.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isWeb = size.width > 700;

    return Scaffold(
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

                  /// UI UPDATED HERE ↓↓↓
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 21,
                          ),
                          onPressed: () {
                            widget.controller.previousPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.ease,
                            );
                          },
                        ),
                      ),

                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 10),
                              const Text(
                                "What’s your mobile number?",
                                style: TextStyle(
                                  fontSize: 26,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 24),

                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 20,
                                    sigmaY: 20,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Row(
                                      children: [
                                        InkWell(
                                          onTap: _showPicker,
                                          child: Row(
                                            children: [
                                              Text(
                                                selectedCountry.flagEmoji,
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                "+${selectedCountry.phoneCode}",
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              const Icon(
                                                Icons.arrow_drop_down,
                                                color: Colors.white70,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: TextField(
                                            controller: _mobileController,
                                            keyboardType: TextInputType.phone,
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                            decoration: const InputDecoration(
                                              border: InputBorder.none,
                                              hintText: "Mobile number",
                                              hintStyle: TextStyle(
                                                color: Colors.white54,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              if (_mobileError != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    _mobileError!,
                                    style: const TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),

                              const SizedBox(height: 26),

                              /// ⭐ NEXT BUTTON MOVED UP ⭐
                              SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: ElevatedButton(
                                  onPressed: _isValid ? _onNext : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isValid
                                        ? const Color(0xFF1877F3)
                                        : Colors.white10,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  child: const Text(
                                    "Next",
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 140),
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
    );
  }
}
