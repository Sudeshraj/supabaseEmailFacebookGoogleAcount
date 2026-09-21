import 'dart:io' show Platform, File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:flutter_application_1/alertBox/time_picker_dialog.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_cropper/image_cropper.dart';
import '../../services/timezone_service.dart';
import '../../utils/image_compression.dart';

// ====================================================================
// CREATE SALON SCREEN — step-by-step wizard
//
// Steps:
//  0. Basic + Contact Info (+ logo/cover)
//  1. Business Hours + Currency
//  2. Review & Create
// ====================================================================
class CreateSalonScreen extends StatefulWidget {
  const CreateSalonScreen({super.key});

  @override
  State<CreateSalonScreen> createState() => _CreateSalonScreenState();
}

class _CreateSalonScreenState extends State<CreateSalonScreen> {
  // ==================== STEP MANAGEMENT ====================
  int _currentStep = 0;
  int _furthestStep = 0;
  static const int _totalSteps = 3;

  // Basic info controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Validation flags
  bool _isPhoneValid = true;
  bool _isEmailValid = true;

  // Images
  File? _logoFile;
  Uint8List? _logoWebBytes;
  File? _coverFile;
  Uint8List? _coverWebBytes;
  bool _isUploadingLogo = false;
  bool _isUploadingCover = false;

  // ==================== TIMEZONE RELATED VARIABLES ====================
  String _openTimeUtc = '';
  String _closeTimeUtc = '';
  TimeOfDay _openTimeLocal = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _closeTimeLocal = const TimeOfDay(hour: 18, minute: 0);
  String _userTimezone = '';
  String _salonTimezone = '';
  bool _isTimezoneLoaded = false;
  bool _isLoading = false;

  // ==================== CURRENCY RELATED VARIABLES ====================
  String _salonCurrencyCode = 'LKR';
  String _salonCurrencySymbol = 'Rs.';

  static const List<Map<String, String>> _supportedCurrencies = [
    {'code': 'LKR', 'symbol': 'Rs.', 'name': 'Sri Lankan Rupee'},
    {'code': 'USD', 'symbol': '\$', 'name': 'US Dollar'},
    {'code': 'INR', 'symbol': '₹', 'name': 'Indian Rupee'},
    {'code': 'GBP', 'symbol': '£', 'name': 'British Pound'},
    {'code': 'EUR', 'symbol': '€', 'name': 'Euro'},
    {'code': 'AUD', 'symbol': 'A\$', 'name': 'Australian Dollar'},
    {'code': 'CAD', 'symbol': 'C\$', 'name': 'Canadian Dollar'},
    {'code': 'SGD', 'symbol': 'S\$', 'name': 'Singapore Dollar'},
    {'code': 'AED', 'symbol': 'د.إ', 'name': 'UAE Dirham'},
    {'code': 'MYR', 'symbol': 'RM', 'name': 'Malaysian Ringgit'},
    {'code': 'THB', 'symbol': '฿', 'name': 'Thai Baht'},
    {'code': 'JPY', 'symbol': '¥', 'name': 'Japanese Yen'},
    {'code': 'CNY', 'symbol': '¥', 'name': 'Chinese Yuan'},
    {'code': 'NZD', 'symbol': 'NZ\$', 'name': 'New Zealand Dollar'},
    {'code': 'CHF', 'symbol': 'CHF', 'name': 'Swiss Franc'},
    {'code': 'PKR', 'symbol': '₨', 'name': 'Pakistani Rupee'},
    {'code': 'BDT', 'symbol': '৳', 'name': 'Bangladeshi Taka'},
    {'code': 'NPR', 'symbol': 'रू', 'name': 'Nepalese Rupee'},
  ];

  bool _isConfirmDialogOpen = false;

  late bool _isWeb;
  late bool _isDark;

  final supabase = Supabase.instance.client;
  final picker = ImagePicker();

  String _getTimezoneDisplay() {
    if (_salonTimezone.isEmpty) {
      return 'Loading timezone...';
    }
    return TimezoneService.getFullTimezoneDisplay();
  }

  @override
  void initState() {
    super.initState();
    _initializeWithTimezone();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTimezoneChanges();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isWeb = context.isWeb;
    _isDark = context.isDarkMode;
  }

  Future<void> _initializeWithTimezone() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();

    String cachedUserTimezone =
        prefs.getString(TimezoneService.kUserTimezone) ?? '';

    if (cachedUserTimezone.isNotEmpty) {
      _userTimezone = cachedUserTimezone;
      await TimezoneService.setTimezone(_userTimezone);
      debugPrint('✅ Timezone from USER SETTING: $_userTimezone');
    } else {
      _userTimezone = TimezoneService.getCurrentTimezone();
      await prefs.setString(TimezoneService.kUserTimezone, _userTimezone);
      debugPrint('✅ Timezone from SERVICE (first time): $_userTimezone');
    }

    _salonTimezone = _userTimezone;

    _detectCurrencyFromTimezone();
    debugPrint('✅ Currency AUTO-DETECTED: $_salonCurrencyCode');

    _initializeBusinessHours();

    setState(() {
      _isTimezoneLoaded = true;
    });
  }

  Future<void> _checkTimezoneChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTimezone =
        prefs.getString(TimezoneService.kUserTimezone) ?? '';

    if (_userTimezone.isNotEmpty && _userTimezone != currentTimezone) {
      debugPrint('🔄 Timezone changed: $_userTimezone → $currentTimezone');

      setState(() {
        _userTimezone = currentTimezone;
        _salonTimezone = currentTimezone;
        _detectCurrencyFromTimezone();
        debugPrint('✅ Currency AUTO-SYNCED: $_salonCurrencyCode');
        _refreshDisplayTimes();
      });
    }
  }

  void _refreshDisplayTimes() {
    if (_openTimeUtc.isNotEmpty) {
      _openTimeLocal = TimezoneService.utcToTimeOfDayWithTimezone(
        _openTimeUtc,
        _salonTimezone,
      );
      _closeTimeLocal = TimezoneService.utcToTimeOfDayWithTimezone(
        _closeTimeUtc,
        _salonTimezone,
      );
    }
    setState(() {});
  }

  void _initializeBusinessHours() {
    const defaultOpenLocal = TimeOfDay(hour: 9, minute: 0);
    const defaultCloseLocal = TimeOfDay(hour: 18, minute: 0);

    _openTimeLocal = defaultOpenLocal;
    _closeTimeLocal = defaultCloseLocal;

    _openTimeUtc = TimezoneService.timeOfDayToUtcWithTimezone(
      defaultOpenLocal,
      _salonTimezone,
    );
    _closeTimeUtc = TimezoneService.timeOfDayToUtcWithTimezone(
      defaultCloseLocal,
      _salonTimezone,
    );

    debugPrint('✅ Business hours initialized');
  }

  void _detectCurrencyFromTimezone() {
    _salonCurrencyCode = TimezoneService.getCurrencyForTimezone(_salonTimezone);
    _salonCurrencySymbol = _getSymbolForCode(_salonCurrencyCode);
  }

  String _getSymbolForCode(String code) {
    return TimezoneService.getSymbolForCurrency(code);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ==================== VALIDATION ====================
  void _validatePhone(String value) {
    setState(() {
      if (value.isEmpty) {
        _isPhoneValid = true;
      } else {
        final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
        if (cleaned.length >= 9 &&
            cleaned.length <= 10 &&
            cleaned.startsWith('0')) {
          _isPhoneValid = true;
        } else {
          _isPhoneValid = false;
        }
      }
    });
  }

  void _validateEmail(String value) {
    setState(() {
      if (value.isEmpty) {
        _isEmailValid = true;
      } else {
        final emailRegex = RegExp(
          r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
        );
        _isEmailValid = emailRegex.hasMatch(value);
      }
    });
  }

  // ==================== STEP VALIDATION ====================

  bool _canProceedFromStep(int step) {
    switch (step) {
      case 0:
        return _nameController.text.trim().isNotEmpty &&
            _isPhoneValid &&
            _isEmailValid;
      case 1:
        return true;
      default:
        return true;
    }
  }

  String _stepRequirementMessage(int step) {
    switch (step) {
      case 0:
        return 'Please enter a salon name (and a valid phone/email if provided)';
      default:
        return '';
    }
  }

  void _goToStep(int step) {
    setState(() {
      _currentStep = step;
      if (step > _furthestStep) _furthestStep = step;
    });
  }

  // ==================== WIDGETS: SHARED HELPERS ====================

  Widget _buildStepHeader(String title, String subtitle) {
    final isDark = _isDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STEP ${_currentStep + 1} OF $_totalSteps',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner(String message, IconData icon, Color color) {
    final isDark = _isDark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.grey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool isPhone = false,
    bool isEmail = false,
  }) {
    final isDark = _isDark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextFormField(
        controller: controller,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: (value) {
          if (isPhone) _validatePhone(value);
          if (isEmail) _validateEmail(value);
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey),
          prefixIcon: Icon(icon, color: isDark ? Colors.white70 : Colors.grey),
          errorText: isPhone && !_isPhoneValid && controller.text.isNotEmpty
              ? 'Enter valid phone number (e.g., 0771234567)'
              : isEmail && !_isEmailValid && controller.text.isNotEmpty
              ? 'Enter valid email address'
              : null,
          errorStyle: TextStyle(color: isDark ? Colors.red[300] : Colors.red),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppTheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
          fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          filled: true,
        ),
      ),
    );
  }

  // ==================== CURRENCY CARD ====================
  Widget _buildCurrencyCard() {
    final isDark = _isDark;

    return Card(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.currency_exchange,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Currency',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 10,
                        color: isDark ? Colors.teal[300] : Colors.teal[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Auto',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.teal[300] : Colors.teal[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Auto-detected from your timezone: $_salonTimezone',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _salonCurrencyCode,
              isExpanded: true,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
              decoration: InputDecoration(
                prefixIcon: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Center(
                    widthFactor: 1.0,
                    child: Text(
                      _salonCurrencySymbol,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 60,
                  minHeight: 20,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              items: _supportedCurrencies.map((currency) {
                return DropdownMenuItem<String>(
                  value: currency['code'],
                  child: Row(
                    children: [
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${currency['code']} - ${currency['name']}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  final selected = _supportedCurrencies.firstWhere(
                    (c) => c['code'] == value,
                  );
                  setState(() {
                    _salonCurrencyCode = value;
                    _salonCurrencySymbol = selected['symbol']!;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: isDark ? Colors.teal[300] : Colors.teal[700],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'All prices will be in $_salonCurrencyCode ($_salonCurrencySymbol).',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.teal[300] : Colors.teal[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== IMAGE SECTION ====================
  Widget _buildCoverSection() {
    final isDesktop = _isWeb;
    final isDark = _isDark;

    return Container(
      height: isDesktop ? 250 : 180,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => _showCoverSourceDialog(),
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
                image: (_coverFile != null || _coverWebBytes != null)
                    ? DecorationImage(
                        image: _coverWebBytes != null
                            ? MemoryImage(_coverWebBytes!)
                            : FileImage(_coverFile!) as ImageProvider,
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: (_coverFile == null && _coverWebBytes == null)
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate,
                            size: isDesktop ? 48 : 36,
                            color: isDark ? Colors.white30 : Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to add cover photo',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
          ),
          if (_coverFile != null || _coverWebBytes != null)
            Positioned(
              bottom: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => _showCoverSourceDialog(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.edit, size: 14, color: Colors.white),
                      SizedBox(width: 4),
                      Text(
                        'Edit',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLogoSeparate() {
    final isDesktop = _isWeb;
    final isDark = _isDark;

    return Container(
      margin: const EdgeInsets.only(left: 16, top: 0, bottom: 16),
      child: GestureDetector(
        onTap: () => _showLogoSourceDialog(),
        child: Container(
          width: isDesktop ? 100 : 80,
          height: isDesktop ? 100 : 80,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            image: (_logoFile != null || _logoWebBytes != null)
                ? DecorationImage(
                    image: _logoWebBytes != null
                        ? MemoryImage(_logoWebBytes!)
                        : FileImage(_logoFile!) as ImageProvider,
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: (_logoFile == null && _logoWebBytes == null)
              ? Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo,
                        size: isDesktop ? 30 : 24,
                        color: isDark ? Colors.white70 : Colors.grey[600],
                      ),
                      SizedBox(height: isDesktop ? 4 : 2),
                      Text(
                        'Add Logo',
                        style: TextStyle(
                          fontSize: isDesktop ? 10 : 8,
                          color: isDark ? Colors.white70 : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Colors.transparent,
                      radius: 50,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(
                          Icons.edit,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  void _showLogoSourceDialog() {
    final isDark = _isDark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Add Logo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppTheme.primary),
              title: Text(
                'Choose from Gallery',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickLogo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppTheme.primary),
              title: Text(
                'Take a Photo',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
                _takeLogoPhoto();
              },
            ),
            if (_logoFile != null || _logoWebBytes != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  'Remove Logo',
                  style: TextStyle(
                    color: isDark ? Colors.red[300] : Colors.red,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _removeLogo();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  void _showCoverSourceDialog() {
    final isDark = _isDark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Add Cover Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppTheme.primary),
              title: Text(
                'Choose from Gallery',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickCover();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppTheme.primary),
              title: Text(
                'Take a Photo',
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
                _takeCoverPhoto();
              },
            ),
            if (_coverFile != null || _coverWebBytes != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  'Remove Cover',
                  style: TextStyle(
                    color: isDark ? Colors.red[300] : Colors.red,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _removeCover();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _pickLogo() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final rawBytes = await pickedFile.readAsBytes();
          final compressed = await compressAvatarBytes(rawBytes);
          setState(() {
            _logoWebBytes = compressed;
            _logoFile = null;
          });
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Logo',
                toolbarColor: AppTheme.primary,
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.square,
                lockAspectRatio: true,
              ),
              IOSUiSettings(title: 'Crop Logo', aspectRatioLockEnabled: true),
            ],
          );
          if (croppedFile != null) {
            final rawBytes = await File(croppedFile.path).readAsBytes();
            final compressed = await compressAvatarBytes(rawBytes);
            setState(() {
              _logoWebBytes = compressed;
              _logoFile = null;
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error picking logo', Colors.red);
    }
  }

  Future<void> _takeLogoPhoto() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final rawBytes = await pickedFile.readAsBytes();
          final compressed = await compressAvatarBytes(rawBytes);
          setState(() {
            _logoWebBytes = compressed;
            _logoFile = null;
          });
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Logo',
                toolbarColor: AppTheme.primary,
                toolbarWidgetColor: Colors.white,
                lockAspectRatio: true,
              ),
              IOSUiSettings(title: 'Crop Logo', aspectRatioLockEnabled: true),
            ],
          );
          if (croppedFile != null) {
            final rawBytes = await File(croppedFile.path).readAsBytes();
            final compressed = await compressAvatarBytes(rawBytes);
            setState(() {
              _logoWebBytes = compressed;
              _logoFile = null;
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error taking photo', Colors.red);
    }
  }

  void _removeLogo() {
    setState(() {
      _logoFile = null;
      _logoWebBytes = null;
    });
  }

  Future<void> _pickCover() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        maxHeight: 1350,
        imageQuality: 90,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final rawBytes = await pickedFile.readAsBytes();
          final compressed = await compressCoverBytes(rawBytes);
          setState(() {
            _coverWebBytes = compressed;
            _coverFile = null;
          });
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Cover',
                toolbarColor: AppTheme.primary,
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.ratio16x9,
                lockAspectRatio: true,
              ),
              IOSUiSettings(title: 'Crop Cover', aspectRatioLockEnabled: true),
            ],
          );
          if (croppedFile != null) {
            final rawBytes = await File(croppedFile.path).readAsBytes();
            final compressed = await compressCoverBytes(rawBytes);
            setState(() {
              _coverWebBytes = compressed;
              _coverFile = null;
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error picking cover', Colors.red);
    }
  }

  Future<void> _takeCoverPhoto() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        maxHeight: 1350,
        imageQuality: 90,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final rawBytes = await pickedFile.readAsBytes();
          final compressed = await compressCoverBytes(rawBytes);
          setState(() {
            _coverWebBytes = compressed;
            _coverFile = null;
          });
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Cover',
                toolbarColor: AppTheme.primary,
                toolbarWidgetColor: Colors.white,
                lockAspectRatio: true,
              ),
              IOSUiSettings(title: 'Crop Cover', aspectRatioLockEnabled: true),
            ],
          );
          if (croppedFile != null) {
            final rawBytes = await File(croppedFile.path).readAsBytes();
            final compressed = await compressCoverBytes(rawBytes);
            setState(() {
              _coverWebBytes = compressed;
              _coverFile = null;
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error taking photo', Colors.red);
    }
  }

  void _removeCover() {
    setState(() {
      _coverFile = null;
      _coverWebBytes = null;
    });
  }

  Future<String?> _uploadLogo(int salonId) async {
    if (_logoFile == null && _logoWebBytes == null) return null;
    setState(() => _isUploadingLogo = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final filePath = 'salons/$userId/$salonId/logo.jpg';

      if (_logoWebBytes != null) {
        await supabase.storage
            .from('salon-images')
            .uploadBinary(
              filePath,
              _logoWebBytes!,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
      } else if (_logoFile != null) {
        await supabase.storage
            .from('salon-images')
            .upload(
              filePath,
              _logoFile!,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
      } else {
        return null;
      }

      final baseUrl = supabase.storage
          .from('salon-images')
          .getPublicUrl(filePath);
      return '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('❌ Error uploading logo: $e');
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  Future<String?> _uploadCover(int salonId) async {
    if (_coverFile == null && _coverWebBytes == null) return null;
    setState(() => _isUploadingCover = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final filePath = 'salons/$userId/$salonId/cover.jpg';

      if (_coverWebBytes != null) {
        await supabase.storage
            .from('salon-images')
            .uploadBinary(
              filePath,
              _coverWebBytes!,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
      } else if (_coverFile != null) {
        await supabase.storage
            .from('salon-images')
            .upload(
              filePath,
              _coverFile!,
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'image/jpeg',
              ),
            );
      } else {
        return null;
      }

      final baseUrl = supabase.storage
          .from('salon-images')
          .getPublicUrl(filePath);
      return '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('❌ Error uploading cover: $e');
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingCover = false);
    }
  }

  // ==================== BUSINESS HOURS CARD ====================
  Widget _buildBusinessHoursCard() {
    final isDark = _isDark;

    return Card(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Business Hours',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _getTimezoneDisplay(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.access_time,
                    size: 14,
                    color: AppTheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TimePickerField(
                    label: 'Open Time',
                    initialTime: _openTimeLocal,
                    isRequired: true,
                    onTimeSelected: (time) {
                      setState(() {
                        _openTimeLocal = time;
                        _openTimeUtc =
                            TimezoneService.timeOfDayToUtcWithTimezone(
                              time,
                              _salonTimezone,
                            );
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TimePickerField(
                    label: 'Close Time',
                    initialTime: _closeTimeLocal,
                    isRequired: true,
                    onTimeSelected: (time) {
                      setState(() {
                        _closeTimeLocal = time;
                        _closeTimeUtc =
                            TimezoneService.timeOfDayToUtcWithTimezone(
                              time,
                              _salonTimezone,
                            );
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2A2A2A) : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: isDark ? Colors.white70 : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Times are stored in UTC. Your local time: ${_openTimeLocal.format(context)} - ${_closeTimeLocal.format(context)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== STEP: REVIEW ====================

  Widget _buildReviewTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onEdit,
  }) {
    final isDark = _isDark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('Edit')),
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Review & Create',
          'Check everything below, then tap "Create Salon" to finish.',
        ),
        _buildReviewTile(
          icon: Icons.store,
          title: 'Salon Name',
          value: _nameController.text.trim().isEmpty
              ? 'Not set'
              : _nameController.text.trim(),
          onEdit: () => _goToStep(0),
        ),
        _buildReviewTile(
          icon: Icons.access_time,
          title: 'Business Hours & Currency',
          value:
              '${_openTimeLocal.format(context)} - ${_closeTimeLocal.format(context)} · $_salonCurrencyCode ($_salonCurrencySymbol)',
          onEdit: () => _goToStep(1),
        ),
        const SizedBox(height: 8),
        _buildInfoBanner(
          'Tapping "Create Salon" will save the salon with the details above.',
          Icons.info_outline,
          AppTheme.primary,
        ),
      ],
    );
  }

  // ==================== CREATE SALON ====================
  Future<void> _onCreateSalonPressed() async {
    for (int step = 0; step <= 2; step++) {
      if (!_canProceedFromStep(step)) {
        _goToStep(step);
        _showSnackBar(_stepRequirementMessage(step), Colors.orange);
        return;
      }
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnackBar('Please login first', Colors.red);
      return;
    }

    if (_isConfirmDialogOpen) return;
    _isConfirmDialogOpen = true;

    final confirmed = await showCustomAlert(
      context: context,
      title: "Create Salon?",
      message:
          'Do you want to create "${_nameController.text.trim()}"?\n\n'
          'Currency: $_salonCurrencyCode ($_salonCurrencySymbol)\n'
          'Timezone: $_salonTimezone\n\n'
          'This will save the salon with everything you\'ve set up.',
      isError: false,
      buttonText: "Create",
      buttonIcon: Icons.add_business,
      showCancelButton: true,
      cancelButtonText: "Cancel",
    );

    _isConfirmDialogOpen = false;

    if (!mounted) return;
    if (confirmed != true) return;

    await _performCreateSalon();
  }

  Future<void> _performCreateSalon() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        _showSnackBar('Please login first', Colors.red);
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final userTimezone =
          prefs.getString(TimezoneService.kUserTimezone) ??
          TimezoneService.getCurrentTimezone();

      final extraData = {
        'created_from': _isWeb ? 'web' : 'mobile',
        'platform': _getPlatformName(),
        'user_timezone': userTimezone,
      };

      final salonData = {
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        'owner_id': userId,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'logo_url': null,
        'cover_url': null,
        'open_time': _openTimeUtc,
        'close_time': _closeTimeUtc,
        'timezone': _salonTimezone,
        'currency_code': _salonCurrencyCode,
        'currency_symbol': _salonCurrencySymbol,
        'extra_data': extraData,
        'is_active': true,
      };

      final response = await supabase
          .from('salons')
          .insert(salonData)
          .select('id, name')
          .single();
      final salonId = response['id'] as int;
      debugPrint('✅ Salon created with ID: $salonId');

      String? logoUrl = (_logoFile != null || _logoWebBytes != null)
          ? await _uploadLogo(salonId)
          : null;
      String? coverUrl = (_coverFile != null || _coverWebBytes != null)
          ? await _uploadCover(salonId)
          : null;

      if (logoUrl != null || coverUrl != null) {
        final imageUpdate = <String, dynamic>{};
        if (logoUrl != null) imageUpdate['logo_url'] = logoUrl;
        if (coverUrl != null) imageUpdate['cover_url'] = coverUrl;
        await supabase.from('salons').update(imageUpdate).eq('id', salonId);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('❌ Error creating salon: $e');
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getPlatformName() => kIsWeb
      ? 'web'
      : Platform.isIOS
      ? 'ios'
      : Platform.isAndroid
      ? 'android'
      : 'mobile';

  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ==================== STEP CONTENT SWITCH ====================

  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Basic & Contact Information',
          'Add your salon\'s core details and how customers can reach you.',
        ),
        _buildCoverSection(),
        Transform.translate(
          offset: const Offset(16, -40),
          child: Align(
            alignment: Alignment.topLeft,
            child: _buildLogoSeparate(),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Basic Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _nameController,
                  label: 'Salon Name *',
                  hint: 'Enter salon name',
                  icon: Icons.store,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _addressController,
                  label: 'Address',
                  hint: 'Enter address',
                  icon: Icons.location_on,
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _descriptionController,
                  label: 'Description',
                  hint: 'Tell about your salon',
                  icon: Icons.description,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contact Information',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  hint: 'Enter phone number (e.g., 0771234567)',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  isPhone: true,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  hint: 'Enter email address (e.g., salon@example.com)',
                  icon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                  isEmail: true,
                ),
                const SizedBox(height: 8),
                Text(
                  'Phone and email are optional but recommended',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Business Hours & Currency',
          'Set your working hours; the currency is auto-detected but you can change it.',
        ),
        _buildBusinessHoursCard(),
        const SizedBox(height: 16),
        _buildCurrencyCard(),
      ],
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildStep0();
      case 1:
        return _buildStep1();
      case 2:
        return _buildReviewStep();
      default:
        return const SizedBox();
    }
  }

  // ==================== STEP INDICATOR ====================

  static const List<Map<String, dynamic>> _stepMeta = [
    {'label': 'Basic', 'icon': Icons.store},
    {'label': 'Hours', 'icon': Icons.access_time},
    {'label': 'Review', 'icon': Icons.check_circle},
  ];

  Widget _buildStepIndicatorRow() {
    final isMobile = !_isWeb;

    return Container(
      color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 20,
          vertical: isMobile ? 12 : 16,
        ),
        child: Row(
          children: [
            for (int i = 0; i < _stepMeta.length; i++) ...[
              _buildStepCircle(
                i,
                _stepMeta[i]['label'] as String,
                _stepMeta[i]['icon'] as IconData,
                isMobile,
              ),
              if (i != _stepMeta.length - 1)
                Container(
                  width: isMobile ? 18 : 30,
                  height: 2,
                  color: _furthestStep > i
                      ? AppTheme.primary
                      : Colors.grey[300],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepCircle(
    int step,
    String label,
    IconData icon,
    bool isMobile,
  ) {
    final isActive = _currentStep == step;
    final isCompleted = _furthestStep > step;
    final isDark = _isDark;
    final size = isMobile ? 34.0 : 42.0;
    final iconSize = isMobile ? 16.0 : 20.0;
    final canTap = step <= _furthestStep;

    return GestureDetector(
      onTap: canTap ? () => _goToStep(step) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? AppTheme.primary
                  : (isActive
                        ? AppTheme.primary.withValues(alpha: 0.1)
                        : (isDark ? Colors.grey[800] : Colors.grey[200])),
              border: Border.all(
                color: isActive
                    ? AppTheme.primary
                    : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
                width: isActive ? 2 : 1.5,
              ),
            ),
            child: Center(
              child: isCompleted
                  ? Icon(Icons.check, size: iconSize, color: Colors.white)
                  : Icon(
                      icon,
                      size: iconSize,
                      color: isActive ? AppTheme.primary : Colors.grey[500],
                    ),
            ),
          ),
          if (!isMobile) ...[
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive
                    ? AppTheme.primary
                    : (isDark ? Colors.white60 : Colors.grey[500]),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== STEP ACTIONS ====================
  // ✅ Lives at the bottom of the scroll content (not a fixed
  // bottomNavigationBar). Both buttons share the row width via
  // Expanded so they never overlap on mobile/narrow screens, and
  // the row itself is centered on wider (web) screens.

  Widget _buildStepActions() {
    final isDark = _isDark;
    final isLastStep = _currentStep == 2;
    final canProceed = _canProceedFromStep(_currentStep);
    final busy = _isLoading || _isUploadingLogo || _isUploadingCover;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      busy ? null : () => setState(() => _currentStep--),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.arrow_back, size: 18),
                        SizedBox(width: 6),
                        Text('Back'),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: _currentStep > 0 ? 2 : 1,
              child: ElevatedButton(
                onPressed: busy
                    ? null
                    : () {
                        if (!canProceed) {
                          _showSnackBar(
                            _stepRequirementMessage(_currentStep),
                            Colors.orange,
                          );
                          return;
                        }
                        if (isLastStep) {
                          _onCreateSalonPressed();
                        } else {
                          setState(() {
                            _currentStep++;
                            if (_currentStep > _furthestStep) {
                              _furthestStep = _currentStep;
                            }
                          });
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: canProceed
                      ? AppTheme.primary
                      : (isDark ? Colors.grey[800] : Colors.grey[300]),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: busy
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              _isUploadingLogo || _isUploadingCover
                                  ? 'Uploading...'
                                  : 'Creating...',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isLastStep ? 'Create Salon' : 'Continue',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isLastStep
                                  ? Icons.check_circle
                                  : Icons.arrow_forward,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final isWeb = context.isWeb;
    _isWeb = isWeb;
    _isDark = isDark;

    if (!_isTimezoneLoaded) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        appBar: AppBar(
          title: const Text('Create New Salon'),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
        ),
        body: const Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(),
                ),
                SizedBox(height: 16),
                Text('Loading timezone...'),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: const Text(
          'Create New Salon',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
      ),
      // ✅ No fixed bottomNavigationBar anymore — the Continue/Create
      // Salon action row now lives at the bottom of the scrollable
      // content (see _buildStepActions), so it never overlaps other
      // content on narrow/mobile screens and stays responsive.
      body: SafeArea(
        child: Container(
          color: isDark ? const Color(0xFF121212) : Colors.grey[50],
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isWeb ? 1000 : double.infinity,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildStepIndicatorRow(),
                    Padding(
                      padding: EdgeInsets.all(isWeb ? 32 : 16),
                      child: _buildStepContent(),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        isWeb ? 32 : 16,
                        0,
                        isWeb ? 32 : 16,
                        isWeb ? 32 : 16,
                      ),
                      child: _buildStepActions(),
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