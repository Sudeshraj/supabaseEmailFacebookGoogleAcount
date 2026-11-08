import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
// EDIT BUSINESS SCREEN (class name EditSalonScreen is unchanged)
// View + Edit modes
//
// VIEW MODE (default):
//  - Shows ONLY the data saved in the DB (raw, no local timezone
//    conversion). Business hours are shown in the business's own timezone.
//  - AppBar: [Edit] [Delete]
//
// EDIT MODE:
//  - Step-by-step wizard (mirrors CreateSalonScreen).
//  Steps:
//   0. Basic (name, business type) + Location + Contact Info (+ logo/cover)
//   1. Business Hours + Currency
//   2. Review & Save
//  - When editing, business hours are converted to the USER's local
//    timezone so the picker feels natural. On save they are converted
//    back to the business's timezone and stored as UTC.
//  - Currency starts from the DB value; user can change it manually.
//  - Phone: country code picker + number, saved in E.164 (+94771234567).
//    An old local number (0771234567) is read using the business country.
//  - Location: country, province, district, city (+ free text address).
//  - Business type: loaded from the business_types table.
//  - AppBar: [Cancel] [Save]
// ====================================================================
class EditSalonScreen extends StatefulWidget {
  final int salonId;

  const EditSalonScreen({super.key, required this.salonId});

  @override
  State<EditSalonScreen> createState() => _EditSalonScreenState();
}

class _EditSalonScreenState extends State<EditSalonScreen> {
  // ✅ Default business timezone (DB default — NOT user timezone)
  static const String _kDefaultSalonTimezone = 'Asia/Colombo';

  // Default phone / address country (ISO) when nothing else is known
  static const String _kDefaultPhoneIso = 'LK';

  // ==================== MODE ====================
  bool _isEditMode = false;

  // ==================== STEP MANAGEMENT ====================
  int _currentStep = 0;
  int _furthestStep = 0;
  static const int _totalSteps = 3;

  // Basic info controllers
  final TextEditingController _nameController = TextEditingController();
  // _addressController = address (free text, exactly as typed)
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _provinceController = TextEditingController();
  final TextEditingController _districtController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Validation flags
  bool _isPhoneValid = true;
  bool _isEmailValid = true;

  // Phone exactly as saved in the DB (VIEW mode)
  String _dbPhone = '';

  // ==================== PHONE COUNTRY CODE ====================
  // ISO country code of the selected dial code (e.g. 'LK' → +94)
  String _phoneIso = _kDefaultPhoneIso;

  // Country list (iso / name / dial / flag) lives in TimezoneService
  List<Map<String, String>> get _supportedDialCodes =>
      TimezoneService.countryDialList;

  Map<String, String> get _currentDialEntry => _supportedDialCodes.firstWhere(
    (c) => c['iso'] == _phoneIso,
    orElse: () => _supportedDialCodes.first,
  );

  String get _currentDial => _currentDialEntry['dial']!;
  String get _currentDialFlag => _currentDialEntry['flag']!;

  // ==================== ADDRESS COUNTRY ====================
  // ISO country code of the salon address (used for filtering salons)
  String _countryIso = _kDefaultPhoneIso;

  Map<String, String> get _countryEntry => _supportedDialCodes.firstWhere(
    (c) => c['iso'] == _countryIso,
    orElse: () => _supportedDialCodes.first,
  );

  String get _countryName => _countryEntry['name']!;
  String get _countryFlag => _countryEntry['flag']!;

  // Images
  File? _logoFile;
  Uint8List? _logoWebBytes;
  File? _coverFile;
  Uint8List? _coverWebBytes;
  String? _currentLogoUrl;
  String? _currentCoverUrl;
  bool _isUploadingLogo = false;
  bool _isUploadingCover = false;

  bool _logoRemoved = false;
  bool _coverRemoved = false;

  // ==================== TIMEZONE ====================
  String _userTimezone = '';
  String _salonTimezone = '';
  String _openTimeUtc = '';
  String _closeTimeUtc = '';
  TimeOfDay? _openTimeLocal; // EDIT MODE (user tz)
  TimeOfDay? _closeTimeLocal; // EDIT MODE (user tz)
  TimeOfDay? _openTimeSalonLocal; // VIEW MODE (business tz)
  TimeOfDay? _closeTimeSalonLocal; // VIEW MODE (business tz)
  bool _isTimezoneLoaded = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDeleting = false;

  // ==================== CURRENCY ====================
  String _dbCurrencyCode = 'LKR';
  String _dbCurrencySymbol = 'Rs.';
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

  // ==================== BUSINESS TYPE (loaded from DB) ====================
  List<Map<String, dynamic>> _businessTypes = [];
  int? _selectedBusinessTypeId;
  bool _isLoadingBusinessTypes = true;
  bool _businessTypesLoadFailed = false;

  /// Business type is required, unless the list could not be loaded at all
  /// (then the owner is not blocked from creating the salon).
  bool get _isBusinessTypeValid =>
      _businessTypes.isEmpty || _selectedBusinessTypeId != null;

  String? get _selectedBusinessTypeName {
    if (_selectedBusinessTypeId == null) return null;
    for (final t in _businessTypes) {
      if (t['id'] == _selectedBusinessTypeId) {
        return t['display_name'] as String?;
      }
    }
    return null;
  }

  final supabase = Supabase.instance.client;
  final picker = ImagePicker();

  late bool _isWeb;
  late bool _isDark;

  // ============================================
  // ✅ TIMEZONE DISPLAY HELPERS (with fallback)
  // ============================================
  String _getSalonTimezoneDisplay() {
    final tz = _salonTimezone.isEmpty ? _kDefaultSalonTimezone : _salonTimezone;
    return tz;
  }

  String _getUserTimezoneDisplay() {
    final tz = _userTimezone.isEmpty ? _kDefaultSalonTimezone : _userTimezone;
    return tz;
  }

  /// ✅ Check if business and user timezones differ
  bool get _isSameTimezone {
    final salonTz = _salonTimezone.isEmpty
        ? _kDefaultSalonTimezone
        : _salonTimezone;
    final userTz = _userTimezone.isEmpty
        ? _kDefaultSalonTimezone
        : _userTimezone;
    return salonTz == userTz;
  }

  /// ✅ Cleaner symbol lookup
  String _getSymbolForCode(String code) {
    for (final c in _supportedCurrencies) {
      if (c['code'] == code) {
        return c['symbol'] ?? 'Rs.';
      }
    }
    return 'Rs.';
  }

  // ============================================
  // ✅ PHONE: read the number saved in the DB
  //   '+94771234567' → country LK + '771234567'
  //   '0771234567' (old format) → business country + '0771234567'
  // ============================================
  void _applyStoredPhone(String raw) {
    final stored = raw.trim();
    if (stored.isEmpty) {
      _phoneController.text = '';
      _phoneIso = _countryIso;
      return;
    }

    if (stored.startsWith('+')) {
      final digits = stored.replaceAll(RegExp(r'[^0-9]'), '');

      // longest dial code that matches
      String? bestDial;
      for (final c in _supportedDialCodes) {
        final dd = c['dial']!.substring(1);
        if (digits.startsWith(dd) &&
            (bestDial == null || c['dial']!.length > bestDial.length)) {
          bestDial = c['dial'];
        }
      }

      if (bestDial != null) {
        // shared dial code (+1): prefer the business country
        final sameDialIso = _supportedDialCodes.firstWhere(
          (c) => c['iso'] == _countryIso && c['dial'] == bestDial,
          orElse: () =>
              _supportedDialCodes.firstWhere((c) => c['dial'] == bestDial),
        )['iso']!;
        _phoneIso = sameDialIso;
        _phoneController.text = digits.substring(bestDial.length - 1);
        return;
      }
    }

    // old local format
    _phoneIso = _countryIso;
    _phoneController.text = stored;
  }

  @override
  void initState() {
    super.initState();
    _initializeWithTimezone();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isWeb = context.isWeb;
    _isDark = context.isDarkMode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _provinceController.dispose();
    _districtController.dispose();
    _cityController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ============================================
  // INIT
  // ============================================

  Future<void> _initializeWithTimezone() async {
    try {
      await TimezoneService.initialize();
      final prefs = await SharedPreferences.getInstance();

      _userTimezone =
          prefs.getString(TimezoneService.kUserTimezone) ??
          TimezoneService.getCurrentTimezone();

      // ✅ Fallback if empty
      if (_userTimezone.isEmpty) {
        _userTimezone = _kDefaultSalonTimezone;
        debugPrint('⚠️ User TZ empty → default: $_kDefaultSalonTimezone');
      }

      if (!mounted) return;
      setState(() => _isTimezoneLoaded = true);

      await _loadAllData();
    } catch (e) {
      debugPrint('❌ Error initializing timezone: $e');
      if (mounted) {
        setState(() {
          _userTimezone = _kDefaultSalonTimezone;
          _salonTimezone = _kDefaultSalonTimezone;
          _isTimezoneLoaded = true;
          _isLoading = false;
        });
        _showSnackBar('Error loading timezone', Colors.red);
      }
    }
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await _loadSalonData();
      // business types list (own try/catch inside: a failure here must
      // not hide the business data)
      await _loadBusinessTypes();
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      if (mounted) {
        _showSnackBar(
          'Error loading data. Please check your connection.',
          Colors.red,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================
  // ✅ Load business data — .maybeSingle() + explicit "not found"
  // ============================================
  Future<void> _loadSalonData() async {
    final response = await supabase
        .from('salons')
        .select()
        .eq('id', widget.salonId)
        .maybeSingle();

    if (response == null) {
      throw Exception('Business not found');
    }

    _nameController.text = response['name'] ?? '';
    _addressController.text = response['address'] ?? '';
    _emailController.text = response['email'] ?? '';
    _descriptionController.text = response['description'] ?? '';

    _currentLogoUrl = response['logo_url'] as String?;
    _currentCoverUrl = response['cover_url'] as String?;

    // ✅ Business timezone with fallback
    final dbTimezone = response['timezone'] as String?;
    if (dbTimezone != null && dbTimezone.isNotEmpty) {
      _salonTimezone = dbTimezone;
    } else {
      _salonTimezone = _kDefaultSalonTimezone;
      debugPrint('⚠️ Business TZ empty → default: $_kDefaultSalonTimezone');
    }

    // ✅ BUSINESS TYPE (selected id from DB)
    _selectedBusinessTypeId = response['business_type_id'] as int?;

    // ✅ LOCATION: country (fallback: from the business timezone)
    final dbCountry = response['country_code']?.toString() ?? '';
    if (dbCountry.isNotEmpty &&
        _supportedDialCodes.any((c) => c['iso'] == dbCountry)) {
      _countryIso = dbCountry;
    } else {
      final iso = TimezoneService.getIsoForTimezone(_salonTimezone);
      _countryIso = _supportedDialCodes.any((c) => c['iso'] == iso)
          ? iso
          : _kDefaultPhoneIso;
    }
    _provinceController.text = response['province']?.toString() ?? '';
    _districtController.text = response['district']?.toString() ?? '';
    _cityController.text = response['city']?.toString() ?? '';

    // ✅ PHONE (needs _countryIso above for old local numbers)
    _dbPhone = (response['phone'] as String? ?? '').trim();
    _applyStoredPhone(_dbPhone);
    _isPhoneValid = true;
    _isEmailValid = true;

    // ✅ CURRENCY: from DB (fallback to auto-detect if missing)
    final savedCurrencyCode = response['currency_code']?.toString();
    if (savedCurrencyCode != null && savedCurrencyCode.isNotEmpty) {
      _dbCurrencyCode = savedCurrencyCode;
      _dbCurrencySymbol =
          response['currency_symbol']?.toString() ??
          _getSymbolForCode(_dbCurrencyCode);
    } else {
      _dbCurrencyCode = TimezoneService.getCurrencyForTimezone(_salonTimezone);
      _dbCurrencySymbol = TimezoneService.getSymbolForCurrency(_dbCurrencyCode);
    }
    // Working copy for EDIT mode
    _salonCurrencyCode = _dbCurrencyCode;
    _salonCurrencySymbol = _dbCurrencySymbol;

    // ============ TIMES ============
    if (response['open_time'] != null) {
      _openTimeUtc = response['open_time'] as String;
    } else {
      _openTimeUtc = TimezoneService.timeOfDayToUtcWithTimezone(
        const TimeOfDay(hour: 9, minute: 0),
        _salonTimezone,
      );
    }
    if (response['close_time'] != null) {
      _closeTimeUtc = response['close_time'] as String;
    } else {
      _closeTimeUtc = TimezoneService.timeOfDayToUtcWithTimezone(
        const TimeOfDay(hour: 18, minute: 0),
        _salonTimezone,
      );
    }

    // ✅ VIEW MODE: UTC → business timezone
    _openTimeSalonLocal = TimezoneService.utcToTimeOfDayWithTimezone(
      _openTimeUtc,
      _salonTimezone,
    );
    _closeTimeSalonLocal = TimezoneService.utcToTimeOfDayWithTimezone(
      _closeTimeUtc,
      _salonTimezone,
    );

    // ✅ EDIT MODE: UTC → user timezone
    _openTimeLocal = TimezoneService.utcToTimeOfDayWithTimezone(
      _openTimeUtc,
      _userTimezone,
    );
    _closeTimeLocal = TimezoneService.utcToTimeOfDayWithTimezone(
      _closeTimeUtc,
      _userTimezone,
    );
  }

  // ============================================
  // MODE SWITCHING
  // ============================================

  void _enterEditMode() {
    setState(() {
      _isEditMode = true;
      _currentStep = 0;
      _furthestStep = 0;

      // ✅ Re-sync times: UTC → user timezone (fresh)
      _openTimeLocal = TimezoneService.utcToTimeOfDayWithTimezone(
        _openTimeUtc,
        _userTimezone,
      );
      _closeTimeLocal = TimezoneService.utcToTimeOfDayWithTimezone(
        _closeTimeUtc,
        _userTimezone,
      );

      // ✅ Preserve DB currency (don't auto-overwrite!)
      _salonCurrencyCode = _dbCurrencyCode;
      _salonCurrencySymbol = _dbCurrencySymbol;
    });
  }

  void _cancelEditMode() {
    setState(() {
      _isEditMode = false;
      _currentStep = 0;
      _furthestStep = 0;
    });
    _loadAllData();
  }

  // ============================================
  // VALIDATION
  // ============================================

  void _validatePhone(String value) {
    setState(() {
      if (value.trim().isEmpty) {
        _isPhoneValid = true;
      } else {
        final national = _extractNational(value);
        _isPhoneValid = _isNationalNumberValid(national);
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

  bool _canProceedFromStep(int step) {
    switch (step) {
      case 0:
        return _isBusinessTypeValid &&
            _nameController.text.trim().isNotEmpty &&
            _cityController.text.trim().isNotEmpty &&
            _isPhoneValid &&
            _isEmailValid;
      case 1:
        return _openTimeLocal != null && _closeTimeLocal != null;
      default:
        return true;
    }
  }

  String _stepRequirementMessage(int step) {
    switch (step) {
      case 0:
        return 'Please select a business type, enter a business name and city (and a valid phone/email if provided)';
      case 1:
        return 'Please set business hours';
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

  /// Digits the user typed WITHOUT country code and WITHOUT leading 0.
  ///   '0771234567'     → '771234567'
  ///   '077 123 4567'   → '771234567'
  ///   '+94771234567'   → '771234567'
  ///   '0094771234567'  → '771234567'
  String _extractNational(String raw) {
    final trimmed = raw.trim();
    var digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');

    if (trimmed.startsWith('+') || trimmed.startsWith('00')) {
      if (trimmed.startsWith('00') && digits.length >= 2) {
        digits = digits.substring(2);
      }
      final dialDigits = _currentDial.substring(1);
      if (digits.startsWith(dialDigits)) {
        digits = digits.substring(dialDigits.length);
      }
      return digits;
    }

    if (digits.startsWith('0')) digits = digits.substring(1);
    return digits;
  }

  /// Final E.164 value for the DB (e.g. +94771234567). null if empty.
  String? _buildE164() {
    final national = _extractNational(_phoneController.text);
    if (national.isEmpty) return null;
    return '$_currentDial$national';
  }

  /// Number with the country code is valid?
  bool _isNationalNumberValid(String national) {
    if (national.isEmpty) return true; // optional field
    final dialDigits = _currentDial.substring(1);
    if (_phoneIso == 'LK') {
      // Sri Lanka: 9 digits after +94 (e.g. 771234567)
      return national.length == 9;
    }
    // Generic: E.164 allows max 15 digits in total
    return national.length >= 6 &&
        national.length <= 14 &&
        (dialDigits.length + national.length) <= 15;
  }

  /// If the user types / pastes a number that starts with '+', switch the
  /// selected country automatically (longest dial code match).
  void _handlePhoneChanged(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('+')) {
      final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
      final sorted = [..._supportedDialCodes]
        ..sort((a, b) => b['dial']!.length.compareTo(a['dial']!.length));

      for (final c in sorted) {
        final dialDigits = c['dial']!.substring(1);
        if (digits.startsWith(dialDigits)) {
          final rest = digits.substring(dialDigits.length);
          // For shared dial codes (+1) keep the current selection
          final keepCurrent =
              _currentDial == c['dial'] && _phoneIso != c['iso'];
          setState(() {
            if (!keepCurrent) _phoneIso = c['iso']!;
          });
          _phoneController.value = TextEditingValue(
            text: rest,
            selection: TextSelection.collapsed(offset: rest.length),
          );
          break;
        }
      }
    }
    _validatePhone(_phoneController.text);
  }

  void _showDialCodePicker() {
    _showCountryPicker(
      title: 'Select Country Code',
      selectedIso: _phoneIso,
      showDial: true,
      onSelected: (iso) {
        setState(() => _phoneIso = iso);
        _validatePhone(_phoneController.text);
      },
    );
  }

  void _showAddressCountryPicker() {
    _showCountryPicker(
      title: 'Select Country',
      selectedIso: _countryIso,
      showDial: false,
      onSelected: (iso) {
        setState(() {
          _countryIso = iso;
          // phone empty නම් phone code එකත් country එකත් එක්ක sync කරන්න
          if (_phoneController.text.trim().isEmpty) _phoneIso = iso;
        });
      },
    );
  }

  /// Generic searchable country picker (used for dial code AND address country)
  void _showCountryPicker({
    required String title,
    required String selectedIso,
    required bool showDial,
    required void Function(String iso) onSelected,
  }) {
    final isDark = _isDark;
    String query = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final q = query.trim().toLowerCase();
          final list = _supportedDialCodes.where((c) {
            if (q.isEmpty) return true;
            return c['name']!.toLowerCase().contains(q) ||
                c['dial']!.contains(q) ||
                c['iso']!.toLowerCase() == q;
          }).toList();

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        onChanged: (v) => setSheetState(() => query = v),
                        decoration: InputDecoration(
                          hintText: showDial
                              ? 'Search country or code'
                              : 'Search country',
                          hintStyle: TextStyle(
                            color: isDark ? Colors.white70 : Colors.grey,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            color: isDark ? Colors.white70 : Colors.grey,
                          ),
                          filled: true,
                          fillColor: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final c = list[i];
                          final selected = c['iso'] == selectedIso;
                          return ListTile(
                            leading: Text(
                              c['flag']!,
                              style: const TextStyle(fontSize: 24),
                            ),
                            title: Text(
                              c['name']!,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (showDial)
                                  Text(
                                    c['dial']!,
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white70
                                          : Colors.grey[700],
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                if (selected) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.check_circle,
                                    color: AppTheme.primary,
                                    size: 20,
                                  ),
                                ],
                              ],
                            ),
                            onTap: () {
                              Navigator.pop(sheetContext);
                              onSelected(c['iso']!);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ============================================
  // IMAGE FUNCTIONS
  // ============================================

  Future<void> _pickLogo() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (pickedFile == null) return;

      if (kIsWeb) {
        final rawBytes = await pickedFile.readAsBytes();
        final compressed = await compressAvatarBytes(rawBytes);
        if (!mounted) return;
        setState(() {
          _logoWebBytes = compressed;
          _logoFile = null;
          _logoRemoved = false;
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
          if (!mounted) return;
          setState(() {
            _logoWebBytes = compressed;
            _logoFile = null;
            _logoRemoved = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error picking logo: $e');
      if (mounted) _showSnackBar('Error picking logo', Colors.red);
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
      if (pickedFile == null) return;

      if (kIsWeb) {
        final rawBytes = await pickedFile.readAsBytes();
        final compressed = await compressAvatarBytes(rawBytes);
        if (!mounted) return;
        setState(() {
          _logoWebBytes = compressed;
          _logoFile = null;
          _logoRemoved = false;
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
          if (!mounted) return;
          setState(() {
            _logoWebBytes = compressed;
            _logoFile = null;
            _logoRemoved = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error taking logo photo: $e');
      if (mounted) _showSnackBar('Error taking photo', Colors.red);
    }
  }

  void _removeLogo() {
    setState(() {
      _logoFile = null;
      _logoWebBytes = null;
      _currentLogoUrl = null;
      _logoRemoved = true;
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
      if (pickedFile == null) return;

      if (kIsWeb) {
        final rawBytes = await pickedFile.readAsBytes();
        final compressed = await compressCoverBytes(rawBytes);
        if (!mounted) return;
        setState(() {
          _coverWebBytes = compressed;
          _coverFile = null;
          _coverRemoved = false;
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
          if (!mounted) return;
          setState(() {
            _coverWebBytes = compressed;
            _coverFile = null;
            _coverRemoved = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error picking cover: $e');
      if (mounted) _showSnackBar('Error picking cover', Colors.red);
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
      if (pickedFile == null) return;

      if (kIsWeb) {
        final rawBytes = await pickedFile.readAsBytes();
        final compressed = await compressCoverBytes(rawBytes);
        if (!mounted) return;
        setState(() {
          _coverWebBytes = compressed;
          _coverFile = null;
          _coverRemoved = false;
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
          if (!mounted) return;
          setState(() {
            _coverWebBytes = compressed;
            _coverFile = null;
            _coverRemoved = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error taking cover photo: $e');
      if (mounted) _showSnackBar('Error taking photo', Colors.red);
    }
  }

  void _removeCover() {
    setState(() {
      _coverFile = null;
      _coverWebBytes = null;
      _currentCoverUrl = null;
      _coverRemoved = true;
    });
  }

  // ============================================
  // ✅ Upload with throw on error (no silent failure)
  // ============================================

  Future<String?> _uploadLogo() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');
    final filePath = 'salons/$userId/${widget.salonId}/logo.jpg';

    if (_logoFile == null && _logoWebBytes == null) {
      if (_logoRemoved) {
        try {
          await supabase.storage.from('salon-images').remove([filePath]);
        } catch (e) {
          debugPrint('⚠️ Could not delete old logo: $e');
        }
        return null;
      }
      return _currentLogoUrl;
    }

    if (mounted) setState(() => _isUploadingLogo = true);
    try {
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
        return _currentLogoUrl;
      }

      final baseUrl = supabase.storage
          .from('salon-images')
          .getPublicUrl(filePath);
      return '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('❌ Error uploading logo: $e');
      rethrow;
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  Future<String?> _uploadCover() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not logged in');
    final filePath = 'salons/$userId/${widget.salonId}/cover.jpg';

    if (_coverFile == null && _coverWebBytes == null) {
      if (_coverRemoved) {
        try {
          await supabase.storage.from('salon-images').remove([filePath]);
        } catch (e) {
          debugPrint('⚠️ Could not delete old cover: $e');
        }
        return null;
      }
      return _currentCoverUrl;
    }

    if (mounted) setState(() => _isUploadingCover = true);
    try {
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
        return _currentCoverUrl;
      }

      final baseUrl = supabase.storage
          .from('salon-images')
          .getPublicUrl(filePath);
      return '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('❌ Error uploading cover: $e');
      rethrow;
    } finally {
      if (mounted) setState(() => _isUploadingCover = false);
    }
  }

  // ============================================
  // SAVE / UPDATE
  // ============================================

  Future<void> _onSavePressed() async {
    for (int step = 0; step <= 2; step++) {
      if (!_canProceedFromStep(step)) {
        _goToStep(step);
        _showSnackBar(_stepRequirementMessage(step), Colors.orange);
        return;
      }
    }

    if (_isConfirmDialogOpen) return;
    _isConfirmDialogOpen = true;

    final phoneE164 = _buildE164();

    final confirmed = await showCustomAlert(
      context: context,
      title: "Save Changes?",
      message:
          'Do you want to save changes to "${_nameController.text.trim()}"?\n\n'
          '${_selectedBusinessTypeName != null ? 'Type: $_selectedBusinessTypeName\n' : ''}'
          'Location: ${_titleCase(_cityController.text)}, $_countryName\n'
          '${phoneE164 != null ? 'Phone: $phoneE164\n' : ''}'
          'Business Timezone: $_salonTimezone\n'
          'Currency: $_salonCurrencyCode ($_salonCurrencySymbol)\n\n'
          'Business hours are being edited in your local timezone ($_userTimezone) '
          'and will be saved converted to the business\'s timezone ($_salonTimezone).',
      isError: false,
      buttonText: "Save",
      buttonIcon: Icons.save,
      showCancelButton: true,
      cancelButtonText: "Cancel",
    );

    _isConfirmDialogOpen = false;

    if (!mounted) return;
    if (confirmed != true) return;

    await _performUpdateSalon();
  }

  Future<void> _performUpdateSalon() async {
    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      if (_openTimeLocal == null || _closeTimeLocal == null) {
        throw Exception('Business hours are not set');
      }

      // ✅ Handle image upload failures gracefully
      bool imageUploadFailed = false;
      String? logoUrl;
      String? coverUrl;

      try {
        logoUrl = await _uploadLogo();
      } catch (e) {
        debugPrint('❌ Logo upload failed: $e');
        logoUrl = _currentLogoUrl; // Keep existing
        imageUploadFailed = true;
      }

      try {
        coverUrl = await _uploadCover();
      } catch (e) {
        debugPrint('❌ Cover upload failed: $e');
        coverUrl = _currentCoverUrl; // Keep existing
        imageUploadFailed = true;
      }

      // ✅ Direct conversion chain (user tz → business tz → UTC)
      final openTimeSalon = TimezoneService.convertTimeOfDayBetweenTimezones(
        _openTimeLocal!,
        fromTimezone: _userTimezone,
        toTimezone: _salonTimezone,
      );
      final closeTimeSalon = TimezoneService.convertTimeOfDayBetweenTimezones(
        _closeTimeLocal!,
        fromTimezone: _userTimezone,
        toTimezone: _salonTimezone,
      );

      final openTimeUtc = TimezoneService.timeOfDayToUtcWithTimezone(
        openTimeSalon,
        _salonTimezone,
      );
      final closeTimeUtc = TimezoneService.timeOfDayToUtcWithTimezone(
        closeTimeSalon,
        _salonTimezone,
      );

      final updateData = {
        'name': _nameController.text.trim(),
        'business_type_id': _selectedBusinessTypeId,
        // address stays exactly as typed
        'address': _nullIfEmpty(_addressController.text),
        // structured location (used for filters)
        'country_code': _countryIso,
        'province': _nullIfEmpty(_titleCase(_provinceController.text)),
        'district': _nullIfEmpty(_titleCase(_districtController.text)),
        'city': _nullIfEmpty(_titleCase(_cityController.text)),
        // phone is saved in E.164 format (+94771234567) or null
        'phone': _buildE164(),
        'email': _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'logo_url': logoUrl,
        'cover_url': coverUrl,
        'open_time': openTimeUtc,
        'close_time': closeTimeUtc,
        'timezone': _salonTimezone,
        'currency_code': _salonCurrencyCode,
        'currency_symbol': _salonCurrencySymbol,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await supabase.from('salons').update(updateData).eq('id', widget.salonId);

      if (!mounted) return;

      // ✅ Show success dialog (with image warning if uploads failed)
      final imageWarning = imageUploadFailed
          ? '\n\n⚠️ Note: Some images failed to upload. You can retry from Edit mode.'
          : '';

      await showCustomAlert(
        context: context,
        title: "✅ Business Updated!",
        message:
            "${_nameController.text.trim()} has been updated successfully.\n\n"
            "🕐 Your local time: ${_openTimeLocal!.format(context)} - ${_closeTimeLocal!.format(context)} ($_userTimezone)\n"
            "🕐 Business time: ${openTimeSalon.format(context)} - ${closeTimeSalon.format(context)} ($_salonTimezone)$imageWarning",
        isError: false,
      );

      if (!mounted) return;

      // ✅ Return to VIEW mode
      setState(() {
        _isEditMode = false;
        _currentStep = 0;
        _furthestStep = 0;
      });

      await _loadAllData();
    } catch (e) {
      debugPrint('❌ Error updating business: $e');
      if (mounted) _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ============================================
  // DELETE
  // ============================================

  Future<void> _deleteSalon() async {
    final isDark = _isDark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Business',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Are you sure you want to delete '${_nameController.text.trim()}'?",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ This will also delete:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.red[300] : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildDeleteBullet('All appointments', isDark),
                  _buildDeleteBullet('All services', isDark),
                  _buildDeleteBullet('All staff', isDark),
                  _buildDeleteBullet('All reviews', isDark),
                  _buildDeleteBullet('All pricing variants', isDark),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'This action cannot be undone!',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.red[300] : Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white60 : Colors.black87,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'Delete Permanently',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _isDeleting = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        try {
          await supabase.storage.from('salon-images').remove([
            'salons/$userId/${widget.salonId}/logo.jpg',
            'salons/$userId/${widget.salonId}/cover.jpg',
          ]);
        } catch (e) {
          debugPrint('⚠️ Could not delete business images: $e');
        }
      }

      await supabase.from('salons').delete().eq('id', widget.salonId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Business deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('❌ Error deleting business: $e');
      if (mounted) _showSnackBar('Error deleting business', Colors.red);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Widget _buildDeleteBullet(String text, bool isDark) {
    return Text(
      '• $text',
      style: TextStyle(
        fontSize: 13,
        color: isDark ? Colors.white70 : Colors.black87,
      ),
    );
  }

  // ============================================
  // SHARED WIDGETS
  // ============================================

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
    bool isEmail = false,
    bool rebuildOnChange = false,
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
          if (isEmail) _validateEmail(value);
          // Continue button state (required fields) refresh
          if (rebuildOnChange) setState(() {});
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: isDark ? Colors.white70 : Colors.grey),
          prefixIcon: Icon(icon, color: isDark ? Colors.white70 : Colors.grey),
          errorText: isEmail && !_isEmailValid && controller.text.isNotEmpty
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

  // ============================================
  // VIEW MODE — read-only widgets
  // ============================================

  Widget _buildViewContent() {
    final isDark = _isDark;
    final locationLine = _composeFullAddress();

    String dash(String v) => v.trim().isEmpty ? '—' : v.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCoverSectionReadOnly(),
        Transform.translate(
          offset: const Offset(16, -40),
          child: Align(
            alignment: Alignment.topLeft,
            child: _buildLogoSeparateReadOnly(),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          _nameController.text.trim().isEmpty
              ? 'Unnamed Business'
              : _nameController.text.trim(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        if (_selectedBusinessTypeName != null) ...[
          const SizedBox(height: 4),
          Text(
            _selectedBusinessTypeName!,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ],
        if (locationLine.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.location_on,
                size: 16,
                color: isDark ? Colors.white60 : Colors.grey,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  locationLine,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),

        _buildInfoBanner(
          'Viewing data exactly as saved in the database. Tap the Edit button to make changes.',
          Icons.info_outline,
          Colors.blue,
        ),

        _buildViewInfoCard(
          title: 'Basic Information',
          icon: Icons.store,
          rows: [
            _ViewRow(label: 'Name', value: _nameController.text.trim()),
            _ViewRow(
              label: 'Business Type',
              value: _selectedBusinessTypeName ?? '—',
            ),
            _ViewRow(
              label: 'Description',
              value: dash(_descriptionController.text),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _buildViewInfoCard(
          title: 'Location',
          icon: Icons.location_on,
          rows: [
            _ViewRow(label: 'Country', value: '$_countryFlag $_countryName'),
            _ViewRow(
              label: 'Province / State',
              value: dash(_provinceController.text),
            ),
            _ViewRow(label: 'District', value: dash(_districtController.text)),
            _ViewRow(label: 'City / Town', value: dash(_cityController.text)),
            _ViewRow(label: 'Address', value: dash(_addressController.text)),
          ],
        ),
        const SizedBox(height: 12),

        _buildViewInfoCard(
          title: 'Contact Information',
          icon: Icons.phone,
          rows: [
            _ViewRow(label: 'Phone', value: dash(_dbPhone)),
            _ViewRow(label: 'Email', value: dash(_emailController.text)),
          ],
        ),
        const SizedBox(height: 12),

        _buildViewInfoCard(
          title: 'Business Hours',
          icon: Icons.access_time,
          rows: [
            _ViewRow(
              label: 'Open Time',
              value: _openTimeSalonLocal?.format(context) ?? '—',
            ),
            _ViewRow(
              label: 'Close Time',
              value: _closeTimeSalonLocal?.format(context) ?? '—',
            ),
            _ViewRow(
              label: 'Business Timezone',
              value: _getSalonTimezoneDisplay(),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _buildViewInfoCard(
          title: 'Currency',
          icon: Icons.currency_exchange,
          rows: [
            _ViewRow(label: 'Code', value: _dbCurrencyCode),
            _ViewRow(label: 'Symbol', value: _dbCurrencySymbol),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildViewInfoCard({
    required String title,
    required IconData icon,
    required List<_ViewRow> rows,
  }) {
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
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...rows.map(
              (r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 120,
                      child: Text(
                        r.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.grey[600],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        r.value,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
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
    );
  }

  Widget _buildCoverSectionReadOnly() {
    final isDesktop = _isWeb;
    final isDark = _isDark;

    return Container(
      height: isDesktop ? 250 : 180,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
        image: (_currentCoverUrl != null)
            ? DecorationImage(
                image: NetworkImage(_currentCoverUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: _currentCoverUrl == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: isDesktop ? 48 : 36,
                    color: isDark ? Colors.white30 : Colors.grey[400],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No cover photo',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildLogoSeparateReadOnly() {
    final isDesktop = _isWeb;
    final isDark = _isDark;

    return Container(
      margin: const EdgeInsets.only(left: 16, top: 0, bottom: 16),
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
          image: (_currentLogoUrl != null)
              ? DecorationImage(
                  image: NetworkImage(_currentLogoUrl!),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: _currentLogoUrl == null
            ? Container(
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey[800] : Colors.grey[300],
                  shape: BoxShape.circle,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.store,
                      size: isDesktop ? 30 : 24,
                      color: isDark ? Colors.white70 : Colors.grey[600],
                    ),
                    SizedBox(height: isDesktop ? 4 : 2),
                    Text(
                      'No Logo',
                      style: TextStyle(
                        fontSize: isDesktop ? 10 : 8,
                        color: isDark ? Colors.white70 : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }

  // ============================================
  // EDIT MODE — cover/logo (interactive)
  // ============================================

  Widget _buildCoverSection() {
    final isDesktop = _isWeb;
    final isDark = _isDark;

    final hasImage =
        _coverFile != null ||
        _coverWebBytes != null ||
        _currentCoverUrl != null;

    return Container(
      height: isDesktop ? 250 : 180,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 24),
      child: Stack(
        children: [
          GestureDetector(
            onTap: _showCoverSourceDialog,
            child: Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
                image: hasImage
                    ? DecorationImage(
                        image: _getCoverImageProvider(),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: !hasImage
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
          if (hasImage)
            Positioned(
              bottom: 12,
              right: 12,
              child: GestureDetector(
                onTap: _showCoverSourceDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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

  ImageProvider _getCoverImageProvider() {
    if (_coverWebBytes != null) return MemoryImage(_coverWebBytes!);
    if (_coverFile != null) return FileImage(_coverFile!);
    if (_currentCoverUrl != null) return NetworkImage(_currentCoverUrl!);
    // This should never be reached — hasImage check guards it
    return const AssetImage('assets/placeholder.png');
  }

  Widget _buildLogoSeparate() {
    final isDesktop = _isWeb;
    final isDark = _isDark;

    final hasImage =
        _logoFile != null || _logoWebBytes != null || _currentLogoUrl != null;

    return Container(
      margin: const EdgeInsets.only(left: 16, top: 0, bottom: 16),
      child: GestureDetector(
        onTap: _showLogoSourceDialog,
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
            image: hasImage
                ? DecorationImage(
                    image: _getLogoImageProvider(),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: !hasImage
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

  ImageProvider _getLogoImageProvider() {
    if (_logoWebBytes != null) return MemoryImage(_logoWebBytes!);
    if (_logoFile != null) return FileImage(_logoFile!);
    if (_currentLogoUrl != null) return NetworkImage(_currentLogoUrl!);
    // This should never be reached — hasImage check guards it
    return const AssetImage('assets/placeholder.png');
  }

  void _showLogoSourceDialog() {
    final isDark = _isDark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
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
                Navigator.pop(sheetContext);
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
                Navigator.pop(sheetContext);
                _takeLogoPhoto();
              },
            ),
            if (_logoFile != null ||
                _logoWebBytes != null ||
                _currentLogoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  'Remove Logo',
                  style: TextStyle(
                    color: isDark ? Colors.red[300] : Colors.red,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
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
      builder: (sheetContext) => SafeArea(
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
                Navigator.pop(sheetContext);
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
                Navigator.pop(sheetContext);
                _takeCoverPhoto();
              },
            ),
            if (_coverFile != null ||
                _coverWebBytes != null ||
                _currentCoverUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  'Remove Cover',
                  style: TextStyle(
                    color: isDark ? Colors.red[300] : Colors.red,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removeCover();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // ✅ PHONE FIELD (country code picker + number)
  // ============================================================
  Widget _buildPhoneField() {
    final isDark = _isDark;
    final hasText = _phoneController.text.trim().isNotEmpty;
    final showError = hasText && !_isPhoneValid;
    final e164 = _buildE164();

    final errorMessage = _phoneIso == 'LK'
        ? 'Enter valid phone number (e.g., 0771234567)'
        : 'Enter a valid phone number';

    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- Country code button ----------
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _showDialCodePicker,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentDialFlag,
                        style: const TextStyle(fontSize: 20),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _currentDial,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down,
                        color: isDark ? Colors.white70 : Colors.grey[600],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // ---------- Number ----------
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s()]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  onChanged: _handlePhoneChanged,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    hintText: _phoneIso == 'LK' ? '0771234567' : 'Phone number',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white70 : Colors.grey,
                    ),
                    prefixIcon: Icon(
                      Icons.phone,
                      color: isDark ? Colors.white70 : Colors.grey,
                    ),
                    errorText: showError ? errorMessage : null,
                    errorMaxLines: 2,
                    errorStyle: TextStyle(
                      color: isDark ? Colors.red[300] : Colors.red,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: AppTheme.primary,
                        width: 2,
                      ),
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
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 11,
                color: isDark ? Colors.teal[300] : Colors.teal[700],
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  (e164 != null && _isPhoneValid)
                      ? 'Will be saved as $e164 (works with WhatsApp / SMS / calls)'
                      : 'Country code auto-detected from business timezone — tap to change',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.teal[300] : Colors.teal[700],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ ADDRESS HELPERS (structured address)
  // ============================================================

  /// "colombo 03" → "Colombo 03"  (so filters group the same city together)
  String _titleCase(String input) {
    final cleaned = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return '';
    return cleaned
        .split(' ')
        .map(
          (w) =>
              w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase(),
        )
        .join(' ');
  }

  /// Location summary for the review step (display only, NOT saved).
  /// The `address` column keeps exactly what the user typed.
  String _composeFullAddress() {
    final parts = [
      _addressController.text.trim(),
      _titleCase(_cityController.text),
      _titleCase(_districtController.text),
      _titleCase(_provinceController.text),
      _countryName,
    ].where((p) => p.isNotEmpty);
    return parts.join(', ');
  }

  String? _nullIfEmpty(String value) =>
      value.trim().isEmpty ? null : value.trim();

  /// Country selector (looks like a text field, opens the country picker)
  Widget _buildCountryField() {
    final isDark = _isDark;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[300]!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _showAddressCountryPicker,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Country *',
                prefixIcon: Icon(
                  Icons.public,
                  color: isDark ? Colors.white70 : Colors.grey,
                ),
                suffixIcon: Icon(
                  Icons.arrow_drop_down,
                  color: isDark ? Colors.white70 : Colors.grey[600],
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: borderColor),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                filled: true,
              ),
              child: Row(
                children: [
                  Text(_countryFlag, style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _countryName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                size: 11,
                color: isDark ? Colors.teal[300] : Colors.teal[700],
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Auto-detected from business timezone — tap to change',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.teal[300] : Colors.teal[700],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ✅ BUSINESS TYPE (loaded from the business_types table)
  // ============================================================
  Future<void> _loadBusinessTypes() async {
    if (mounted) {
      setState(() {
        _isLoadingBusinessTypes = true;
        _businessTypesLoadFailed = false;
      });
    }

    try {
      final data = await supabase
          .from('business_types')
          .select('id, code, display_name, icon_name')
          .eq('is_active', true)
          .order('display_order', ascending: true);

      if (!mounted) return;
      setState(() {
        _businessTypes = List<Map<String, dynamic>>.from(data as List);
        _isLoadingBusinessTypes = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading business types: $e');
      if (!mounted) return;
      setState(() {
        _businessTypes = [];
        _isLoadingBusinessTypes = false;
        _businessTypesLoadFailed = true;
      });
    }
  }

  /// business_types.icon_name (text in DB) → Flutter icon
  IconData _businessTypeIcon(String? name) {
    switch (name) {
      case 'content_cut':
        return Icons.content_cut;
      case 'face_retouching_natural':
        return Icons.face_retouching_natural;
      case 'face':
        return Icons.face;
      case 'people':
        return Icons.people;
      case 'spa':
        return Icons.spa;
      case 'back_hand':
        return Icons.back_hand;
      case 'auto_awesome':
        return Icons.auto_awesome;
      case 'camera_alt':
        return Icons.camera_alt;
      case 'brush':
        return Icons.brush;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'local_hospital':
        return Icons.local_hospital;
      case 'local_car_wash':
        return Icons.local_car_wash;
      case 'home_repair_service':
        return Icons.home_repair_service;
      case 'checkroom':
        return Icons.checkroom;
      case 'pets':
        return Icons.pets;
      case 'school':
        return Icons.school;
      case 'celebration':
        return Icons.celebration;
      default:
        return Icons.storefront;
    }
  }

  Widget _buildBusinessTypeSelector() {
    final isDark = _isDark;

    Widget content;
    if (_isLoadingBusinessTypes) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else if (_businessTypesLoadFailed) {
      content = Row(
        children: [
          Expanded(
            child: Text(
              'Could not load business types',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.red[300] : Colors.red,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: _loadBusinessTypes,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      );
    } else if (_businessTypes.isEmpty) {
      content = Text(
        'No business types available',
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white60 : Colors.grey[600],
        ),
      );
    } else {
      content = Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _businessTypes.map((t) {
          final id = t['id'] as int;
          final selected = id == _selectedBusinessTypeId;
          return ChoiceChip(
            avatar: Icon(
              _businessTypeIcon(t['icon_name'] as String?),
              size: 18,
              color: selected ? Colors.white : AppTheme.primary,
            ),
            label: Text(t['display_name'] as String),
            selected: selected,
            showCheckmark: false,
            selectedColor: AppTheme.primary,
            backgroundColor: isDark
                ? const Color(0xFF2A2A2A)
                : Colors.grey[100],
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected
                  ? Colors.white
                  : (isDark ? Colors.white : Colors.black87),
            ),
            onSelected: (_) => setState(() => _selectedBusinessTypeId = id),
          );
        }).toList(),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Business Type *',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          content,
        ],
      ),
    );
  }

  // ============================================
  // BUSINESS HOURS (EDIT MODE)
  // ============================================

  Widget _buildBusinessHoursCard() {
    final isDark = _isDark;
    final showUserTime = !_isSameTimezone;

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

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.public,
                        size: 14,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Business: ${_getSalonTimezoneDisplay()}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showUserTime)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.person_pin_circle,
                          size: 14,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'You: ${_getUserTimezoneDisplay()}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Times below are shown in YOUR local timezone. They will be '
              'converted to the business\'s timezone on save.',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.white60 : Colors.grey,
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
                      setState(() => _openTimeLocal = time);
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
                      setState(() => _closeTimeLocal = time);
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
                      'Your local time: ${_openTimeLocal?.format(context) ?? '—'} - ${_closeTimeLocal?.format(context) ?? '—'} ($_userTimezone)',
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

  // ============================================
  // CURRENCY CARD (EDIT MODE)
  // ============================================

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
              'Auto-suggested from your timezone ($_userTimezone). You can change it.',
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
                      'Currently saved in DB: $_dbCurrencyCode ($_dbCurrencySymbol). '
                      'Saving will set it to $_salonCurrencyCode ($_salonCurrencySymbol).',
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

  // ============================================
  // EDIT MODE — step 2: REVIEW
  // ============================================

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
    final phoneE164 = _buildE164();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Review & Save',
          'Check everything below, then tap "Save Changes" to finish.',
        ),
        _buildReviewTile(
          icon: Icons.store,
          title: 'Business Name',
          value: _nameController.text.trim().isEmpty
              ? 'Not set'
              : _nameController.text.trim(),
          onEdit: () => _goToStep(0),
        ),
        _buildReviewTile(
          icon: Icons.category,
          title: 'Business Type',
          value: _selectedBusinessTypeName ?? 'Not set',
          onEdit: () => _goToStep(0),
        ),
        _buildReviewTile(
          icon: Icons.location_on,
          title: 'Location',
          value: _composeFullAddress().isEmpty
              ? 'Not set'
              : _composeFullAddress(),
          onEdit: () => _goToStep(0),
        ),
        _buildReviewTile(
          icon: Icons.phone,
          title: 'Phone',
          value: phoneE164 ?? 'Not set',
          onEdit: () => _goToStep(0),
        ),
        _buildReviewTile(
          icon: Icons.access_time,
          title: 'Business Hours & Currency',
          value:
              '${_openTimeLocal?.format(context) ?? '—'} - ${_closeTimeLocal?.format(context) ?? '—'} ($_userTimezone) · $_salonCurrencyCode ($_salonCurrencySymbol)',
          onEdit: () => _goToStep(1),
        ),
        _buildReviewTile(
          icon: Icons.public,
          title: 'Business Timezone',
          value: _getSalonTimezoneDisplay(),
          onEdit: () => _goToStep(1),
        ),
        const SizedBox(height: 8),
        _buildInfoBanner(
          'Tapping "Save Changes" will update the business with the details above. Business hours will be converted from your local timezone ($_userTimezone) to the business\'s timezone ($_salonTimezone).',
          Icons.info_outline,
          AppTheme.primary,
        ),
      ],
    );
  }

  // ============================================
  // STEP CONTENT (EDIT MODE)
  // ============================================

  Widget _buildStep0() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(
          'Basic & Contact Information',
          'Edit your business\'s core details and how customers can reach you.',
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
                  label: 'Business Name *',
                  hint: 'Enter business name',
                  icon: Icons.store,
                  rebuildOnChange: true,
                ),
                const SizedBox(height: 12),
                // ✅ Business type (loaded from DB)
                _buildBusinessTypeSelector(),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _descriptionController,
                  label: 'Description',
                  hint: 'Tell about your business',
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
                  'Location',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                _buildCountryField(),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _provinceController,
                  label: 'Province / State',
                  hint: 'Enter province or state',
                  icon: Icons.map,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _districtController,
                  label: 'District',
                  hint: 'Enter district',
                  icon: Icons.account_tree,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _cityController,
                  label: 'City / Town *',
                  hint: 'Enter city or town',
                  icon: Icons.location_city,
                  rebuildOnChange: true,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _addressController,
                  label: 'Address',
                  hint: 'Enter address',
                  icon: Icons.location_on,
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                Text(
                  'Country and city help customers find your business with filters',
                  style: TextStyle(
                    fontSize: 11,
                    color: _isDark ? Colors.white70 : Colors.grey[500],
                  ),
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
                // ✅ Country code picker + phone number
                _buildPhoneField(),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  hint: 'Enter email address (e.g., business@example.com)',
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
          'Edit your working hours. Times are shown in YOUR local timezone; they will be converted to the business\'s timezone on save.',
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

  // ============================================
  // STEP INDICATOR (EDIT MODE)
  // ============================================

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

  // ============================================
  // STEP ACTIONS (EDIT MODE)
  // ============================================

  Widget _buildStepActions() {
    final isDark = _isDark;
    final isLastStep = _currentStep == 2;
    final canProceed = _canProceedFromStep(_currentStep);
    final busy = _isSaving || _isUploadingLogo || _isUploadingCover;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Row(
          children: [
            if (_currentStep > 0) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : () => setState(() => _currentStep--),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(
                      color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                          _onSavePressed();
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
                                  : 'Saving...',
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
                              isLastStep ? 'Save Changes' : 'Continue',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              isLastStep ? Icons.save : Icons.arrow_forward,
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

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ============================================
  // BUILD
  // ============================================

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final isWeb = context.isWeb;
    _isWeb = isWeb;
    _isDark = isDark;

    // Loading state
    if (!_isTimezoneLoaded || _isLoading) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        appBar: AppBar(
          title: Text(_isEditMode ? 'Edit Business' : 'Business Details'),
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
                Text('Loading business data...'),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(
          _isEditMode ? 'Edit Business' : 'Business Details',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
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
        actions: [
          if (!_isEditMode) ...[
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              tooltip: 'Edit',
              onPressed: _enterEditMode,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _isDeleting ? null : _deleteSalon,
              tooltip: 'Delete Business',
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Cancel',
              onPressed: _isSaving ? null : _cancelEditMode,
            ),
            IconButton(
              icon: const Icon(Icons.save, color: Colors.white),
              tooltip: 'Save',
              onPressed: _isSaving ? null : _onSavePressed,
            ),
          ],
        ],
      ),
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
                    if (_isEditMode) _buildStepIndicatorRow(),
                    Padding(
                      padding: EdgeInsets.all(isWeb ? 32 : 16),
                      child: _isEditMode
                          ? _buildStepContent()
                          : _buildViewContent(),
                    ),
                    if (_isEditMode)
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

// ============================================
// Simple value object for view-mode rows
// ============================================
class _ViewRow {
  final String label;
  final String value;
  const _ViewRow({required this.label, required this.value});
}
