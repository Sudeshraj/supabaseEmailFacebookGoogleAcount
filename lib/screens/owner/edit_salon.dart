import 'dart:io' show File;
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
// EDIT SALON SCREEN — View + Edit modes
//
// VIEW MODE (default):
//  - Shows ONLY the data saved in the DB (raw, no local timezone
//    conversion). Business hours are shown in the salon's own timezone.
//  - AppBar: [Edit] [Delete]
//
// EDIT MODE:
//  - Step-by-step wizard (mirrors CreateSalonScreen).
//  Steps:
//   0. Basic + Contact Info (+ logo/cover)
//   1. Business Hours + Currency
//   2. Review & Save
//  - When editing, business hours are converted to the USER's local
//    timezone so the picker feels natural. On save they are converted
//    back to the salon's timezone and stored as UTC.
//  - Currency is auto-synced to the user's timezone when editing, but
//    can be changed manually.
//  - AppBar: [Cancel] [Save]
// ====================================================================
class EditSalonScreen extends StatefulWidget {
  final int salonId;

  const EditSalonScreen({super.key, required this.salonId});

  @override
  State<EditSalonScreen> createState() => _EditSalonScreenState();
}

class _EditSalonScreenState extends State<EditSalonScreen> {
  // ==================== MODE ====================
  bool _isEditMode = false;

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
  String? _currentLogoUrl;
  String? _currentCoverUrl;
  bool _isUploadingLogo = false;
  bool _isUploadingCover = false;

  bool _logoRemoved = false;
  bool _coverRemoved = false;

  // ==================== TIMEZONE ====================
  String _userTimezone = ''; // device timezone
  String _salonTimezone = ''; // DB timezone of the salon
  String _openTimeUtc = '';
  String _closeTimeUtc = '';
  TimeOfDay? _openTimeLocal; // shown in EDIT MODE (user tz)
  TimeOfDay? _closeTimeLocal; // shown in EDIT MODE (user tz)
  TimeOfDay? _openTimeSalonLocal; // shown in VIEW MODE (salon tz)
  TimeOfDay? _closeTimeSalonLocal; // shown in VIEW MODE (salon tz)
  bool _isTimezoneLoaded = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDeleting = false;

  // ==================== CURRENCY ====================
  // Original values from DB (used in VIEW mode)
  String _dbCurrencyCode = 'LKR';
  String _dbCurrencySymbol = 'Rs.';
  // Working values (used in EDIT mode — starts as copy of DB, can change)
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

  final supabase = Supabase.instance.client;
  final picker = ImagePicker();

  late bool _isWeb;
  late bool _isDark;

  /// ✅ VIEW MODE: show the salon's timezone EXACTLY as saved in DB.
  /// (No conversion to user's local timezone.)
  String _getSalonTimezoneDisplay() {
    if (_salonTimezone.isEmpty) return 'Loading...';
    return _salonTimezone;
  }

  /// ✅ EDIT MODE: show the user's local timezone (so the picker makes sense).
  String _getUserTimezoneDisplay() {
    if (_userTimezone.isEmpty) return 'Loading...';
    return _userTimezone;
  }

  String _getSymbolForCode(String code) {
    final match = _supportedCurrencies.firstWhere(
      (c) => c['code'] == code,
      orElse: () => {'symbol': _salonCurrencySymbol},
    );
    return match['symbol'] ?? _salonCurrencySymbol;
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
    _phoneController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ============================================
  // INIT
  // ============================================

  Future<void> _initializeWithTimezone() async {
    await TimezoneService.initialize();
    final prefs = await SharedPreferences.getInstance();
    _userTimezone = prefs.getString('user_timezone') ??
        TimezoneService.getCurrentTimezone();

    setState(() => _isTimezoneLoaded = true);
    await _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _loadSalonData();
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
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSalonData() async {
    final response = await supabase
        .from('salons')
        .select()
        .eq('id', widget.salonId)
        .single();

    _nameController.text = response['name'] ?? '';
    _addressController.text = response['address'] ?? '';
    _phoneController.text = response['phone'] ?? '';
    _emailController.text = response['email'] ?? '';
    _descriptionController.text = response['description'] ?? '';

    _currentLogoUrl = response['logo_url'];
    _currentCoverUrl = response['cover_url'];

    // ✅ SALON TIMEZONE: always from DB
    _salonTimezone =
        response['timezone'] ?? TimezoneService.getCurrentTimezone();

    // ✅ CURRENCY: from DB (fallback to auto-detect if missing)
    final savedCurrencyCode = response['currency_code']?.toString();
    if (savedCurrencyCode != null && savedCurrencyCode.isNotEmpty) {
      _dbCurrencyCode = savedCurrencyCode;
      _dbCurrencySymbol = response['currency_symbol']?.toString() ??
          _getSymbolForCode(_dbCurrencyCode);
    } else {
      _dbCurrencyCode =
          TimezoneService.getCurrencyForTimezone(_salonTimezone);
      _dbCurrencySymbol =
          TimezoneService.getSymbolForCurrency(_dbCurrencyCode);
    }
    // Working copy for EDIT mode starts as the DB values
    _salonCurrencyCode = _dbCurrencyCode;
    _salonCurrencySymbol = _dbCurrencySymbol;

    // ============ TIMES ============
    // Load UTC strings from DB
    if (response['open_time'] != null) {
      _openTimeUtc = response['open_time'] as String;
    } else {
      _openTimeUtc = TimezoneService.timeOfDayToUtcWithTimezone(
          const TimeOfDay(hour: 9, minute: 0), _salonTimezone);
    }
    if (response['close_time'] != null) {
      _closeTimeUtc = response['close_time'] as String;
    } else {
      _closeTimeUtc = TimezoneService.timeOfDayToUtcWithTimezone(
          const TimeOfDay(hour: 18, minute: 0), _salonTimezone);
    }

    // ✅ VIEW MODE: convert UTC → salon timezone (this is the "real" salon time)
    _openTimeSalonLocal = TimezoneService.utcToTimeOfDayWithTimezone(
        _openTimeUtc, _salonTimezone);
    _closeTimeSalonLocal = TimezoneService.utcToTimeOfDayWithTimezone(
        _closeTimeUtc, _salonTimezone);

    // ✅ EDIT MODE: convert UTC → user timezone (so the picker feels natural)
    _openTimeLocal = TimezoneService.utcToTimeOfDayWithTimezone(
        _openTimeUtc, _userTimezone);
    _closeTimeLocal = TimezoneService.utcToTimeOfDayWithTimezone(
        _closeTimeUtc, _userTimezone);
  }

  // ============================================
  // MODE SWITCHING
  // ============================================

  void _enterEditMode() {
    setState(() {
      _isEditMode = true;
      _currentStep = 0;
      _furthestStep = 0;

      // ✅ When entering edit mode, re-sync the working values:
      //  - Times → convert UTC → USER timezone (already done in load,
      //    but re-do it in case user changed device tz)
      _openTimeLocal = TimezoneService.utcToTimeOfDayWithTimezone(
          _openTimeUtc, _userTimezone);
      _closeTimeLocal = TimezoneService.utcToTimeOfDayWithTimezone(
          _closeTimeUtc, _userTimezone);

      //  - Currency → auto-detect from USER's timezone (a fresh suggestion
      //    for the edit session), but user can still override.
      _salonCurrencyCode =
          TimezoneService.getCurrencyForTimezone(_userTimezone);
      _salonCurrencySymbol =
          TimezoneService.getSymbolForCurrency(_salonCurrencyCode);
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
      if (value.isEmpty) {
        _isPhoneValid = true;
      } else {
        final cleaned = value.replaceAll(RegExp(r'[^0-9]'), '');
        _isPhoneValid = cleaned.length >= 9 &&
            cleaned.length <= 10 &&
            cleaned.startsWith('0');
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

  // ============================================
  // STEP VALIDATION
  // ============================================

  bool _canProceedFromStep(int step) {
    switch (step) {
      case 0:
        return _nameController.text.trim().isNotEmpty &&
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
        return 'Please enter a salon name (and a valid phone/email if provided)';
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
      if (pickedFile != null) {
        if (kIsWeb) {
          final rawBytes = await pickedFile.readAsBytes();
          final compressed = await compressAvatarBytes(rawBytes);
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
            setState(() {
              _logoWebBytes = compressed;
              _logoFile = null;
              _logoRemoved = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error picking logo: $e');
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
            setState(() {
              _logoWebBytes = compressed;
              _logoFile = null;
              _logoRemoved = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      _showSnackBar('Error taking photo', Colors.red);
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
      if (pickedFile != null) {
        if (kIsWeb) {
          final rawBytes = await pickedFile.readAsBytes();
          final compressed = await compressCoverBytes(rawBytes);
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
            setState(() {
              _coverWebBytes = compressed;
              _coverFile = null;
              _coverRemoved = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error picking cover: $e');
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
            setState(() {
              _coverWebBytes = compressed;
              _coverFile = null;
              _coverRemoved = false;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error: $e');
      _showSnackBar('Error taking photo', Colors.red);
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

    setState(() => _isUploadingLogo = true);
    try {
      if (_logoWebBytes != null) {
        await supabase.storage.from('salon-images').uploadBinary(
              filePath,
              _logoWebBytes!,
              fileOptions:
                  const FileOptions(upsert: true, contentType: 'image/jpeg'),
            );
      } else if (_logoFile != null) {
        await supabase.storage.from('salon-images').upload(
              filePath,
              _logoFile!,
              fileOptions:
                  const FileOptions(upsert: true, contentType: 'image/jpeg'),
            );
      } else {
        return _currentLogoUrl;
      }

      final baseUrl =
          supabase.storage.from('salon-images').getPublicUrl(filePath);
      return '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('❌ Error uploading logo: $e');
      return _currentLogoUrl;
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

    setState(() => _isUploadingCover = true);
    try {
      if (_coverWebBytes != null) {
        await supabase.storage.from('salon-images').uploadBinary(
              filePath,
              _coverWebBytes!,
              fileOptions:
                  const FileOptions(upsert: true, contentType: 'image/jpeg'),
            );
      } else if (_coverFile != null) {
        await supabase.storage.from('salon-images').upload(
              filePath,
              _coverFile!,
              fileOptions:
                  const FileOptions(upsert: true, contentType: 'image/jpeg'),
            );
      } else {
        return _currentCoverUrl;
      }

      final baseUrl =
          supabase.storage.from('salon-images').getPublicUrl(filePath);
      return '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('❌ Error uploading cover: $e');
      return _currentCoverUrl;
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

    final confirmed = await showCustomAlert(
      context: context,
      title: "Save Changes?",
      message: 'Do you want to save changes to "${_nameController.text.trim()}"?\n\n'
          'Salon Timezone: $_salonTimezone\n'
          'Currency: $_salonCurrencyCode ($_salonCurrencySymbol)\n\n'
          'Business hours are being edited in your local timezone ($_userTimezone) '
          'and will be saved converted to the salon\'s timezone ($_salonTimezone).',
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
    setState(() => _isSaving = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');

      final logoUrl = await _uploadLogo();
      final coverUrl = await _uploadCover();

      // ✅ Convert the user-edited local times → UTC using the SALON's timezone.
      // The picker showed times in the user's local timezone; we first
      // convert those to the salon's timezone, then to UTC.
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
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
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

      await showCustomAlert(
        context: context,
        title: "✅ Salon Updated!",
        message:
            "${_nameController.text.trim()} has been updated successfully.\n\n"
            "🕐 Your local time: ${_openTimeLocal!.format(context)} - ${_closeTimeLocal!.format(context)} ($_userTimezone)\n"
            "🕐 Salon time: ${openTimeSalon.format(context)} - ${closeTimeSalon.format(context)} ($_salonTimezone)",
        isError: false,
      );

      if (!mounted) return;

      // ✅ Return to VIEW mode after successful save
      setState(() {
        _isEditMode = false;
        _currentStep = 0;
        _furthestStep = 0;
      });

      // Reload from DB so VIEW mode shows exactly what's now saved
      await _loadAllData();
    } catch (e) {
      debugPrint('❌ Error updating salon: $e');
      _showSnackBar('Error: $e', Colors.red);
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
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.red, size: 28),
            const SizedBox(width: 12),
            Text(
              'Delete Salon',
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
                  _buildDeleteBullet('All barbers', isDark),
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
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white60 : Colors.black87,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'Delete Permanently',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
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
            debugPrint('⚠️ Could not delete salon images: $e');
          }
        }

        await supabase.from('salons').delete().eq('id', widget.salonId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Salon deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          if (mounted) Navigator.pop(context, true);
        }
      } catch (e) {
        debugPrint('❌ Error deleting salon: $e');
        if (mounted) _showSnackBar('Error deleting salon', Colors.red);
      } finally {
        if (mounted) setState(() => _isDeleting = false);
      }
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover
        _buildCoverSectionReadOnly(),
        Transform.translate(
          offset: const Offset(16, -40),
          child: Align(
            alignment: Alignment.topLeft,
            child: _buildLogoSeparateReadOnly(),
          ),
        ),
        const SizedBox(height: 16),

        // Title
        Text(
          _nameController.text.trim().isEmpty
              ? 'Unnamed Salon'
              : _nameController.text.trim(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        if (_addressController.text.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.location_on,
                  size: 16, color: isDark ? Colors.white60 : Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _addressController.text.trim(),
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

        // ✅ Info banner — everything below is DB data (raw)
        _buildInfoBanner(
          'Viewing data exactly as saved in the database. Tap the Edit button to make changes.',
          Icons.info_outline,
          Colors.blue,
        ),

        // Basic Info
        _buildViewInfoCard(
          title: 'Basic Information',
          icon: Icons.store,
          rows: [
            _ViewRow(label: 'Name', value: _nameController.text.trim()),
            _ViewRow(
                label: 'Address',
                value: _addressController.text.trim().isEmpty
                    ? '—'
                    : _addressController.text.trim()),
            _ViewRow(
                label: 'Description',
                value: _descriptionController.text.trim().isEmpty
                    ? '—'
                    : _descriptionController.text.trim()),
          ],
        ),
        const SizedBox(height: 12),

        // Contact
        _buildViewInfoCard(
          title: 'Contact Information',
          icon: Icons.phone,
          rows: [
            _ViewRow(
                label: 'Phone',
                value: _phoneController.text.trim().isEmpty
                    ? '—'
                    : _phoneController.text.trim()),
            _ViewRow(
                label: 'Email',
                value: _emailController.text.trim().isEmpty
                    ? '—'
                    : _emailController.text.trim()),
          ],
        ),
        const SizedBox(height: 12),

        // ✅ Business Hours — SHOWS SALON TIMEZONE TIMES (no conversion)
        _buildViewInfoCard(
          title: 'Business Hours',
          icon: Icons.access_time,
          rows: [
            _ViewRow(
                label: 'Open Time',
                value: _openTimeSalonLocal?.format(context) ?? '—'),
            _ViewRow(
                label: 'Close Time',
                value: _closeTimeSalonLocal?.format(context) ?? '—'),
            _ViewRow(
                label: 'Salon Timezone',
                value: _getSalonTimezoneDisplay()),
          ],
        ),
        const SizedBox(height: 12),

        // ✅ Currency — from DB
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
            ...rows.map((r) => Padding(
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
                )),
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
                image: (_coverFile != null ||
                        _coverWebBytes != null ||
                        _currentCoverUrl != null)
                    ? DecorationImage(
                        image: _getCoverImageProvider(),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: (_coverFile == null &&
                      _coverWebBytes == null &&
                      _currentCoverUrl == null)
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
                              color:
                                  isDark ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    )
                  : null,
            ),
          ),
          if (_coverFile != null ||
              _coverWebBytes != null ||
              _currentCoverUrl != null)
            Positioned(
              bottom: 12,
              right: 12,
              child: GestureDetector(
                onTap: () => _showCoverSourceDialog(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
    return const AssetImage('placeholder.png');
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
            image: (_logoFile != null ||
                    _logoWebBytes != null ||
                    _currentLogoUrl != null)
                ? DecorationImage(
                    image: _getLogoImageProvider(),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: (_logoFile == null &&
                  _logoWebBytes == null &&
                  _currentLogoUrl == null)
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
    return const AssetImage('placeholder.png');
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
              leading:
                  const Icon(Icons.photo_library, color: AppTheme.primary),
              title: Text(
                'Choose from Gallery',
                style:
                    TextStyle(color: isDark ? Colors.white : Colors.black87),
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
                style:
                    TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
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
                  style:
                      TextStyle(color: isDark ? Colors.red[300] : Colors.red),
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
              leading:
                  const Icon(Icons.photo_library, color: AppTheme.primary),
              title: Text(
                'Choose from Gallery',
                style:
                    TextStyle(color: isDark ? Colors.white : Colors.black87),
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
                style:
                    TextStyle(color: isDark ? Colors.white : Colors.black87),
              ),
              onTap: () {
                Navigator.pop(context);
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
                  style:
                      TextStyle(color: isDark ? Colors.red[300] : Colors.red),
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

  // ============================================
  // BUSINESS HOURS (EDIT MODE)
  // ============================================

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

            // ✅ Two timezone pills: the salon's (from DB) and the user's
            // (the timezone the picker uses while editing).
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.public,
                          size: 14, color: AppTheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Salon: ${_getSalonTimezoneDisplay()}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person_pin_circle,
                          size: 14, color: Colors.teal),
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
              'converted to the salon\'s timezone on save.',
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
                  Icon(Icons.info_outline,
                      size: 14, color: isDark ? Colors.white70 : Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your local time: ${_openTimeLocal?.format(context)} - ${_closeTimeLocal?.format(context)} ($_userTimezone)',
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
                // ✅ Auto badge — shows it was auto-suggested from user tz
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome,
                          size: 10,
                          color:
                              isDark ? Colors.teal[300] : Colors.teal[700]),
                      const SizedBox(width: 4),
                      Text(
                        'Auto',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color:
                              isDark ? Colors.teal[300] : Colors.teal[700],
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
        border:
            Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[200]!),
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
                Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white60 : Colors.grey[600])),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87),
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
          'Review & Save',
          'Check everything below, then tap "Save Changes" to finish.',
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
              '${_openTimeLocal?.format(context)} - ${_closeTimeLocal?.format(context)} ($_userTimezone) · $_salonCurrencyCode ($_salonCurrencySymbol)',
          onEdit: () => _goToStep(1),
        ),
        const SizedBox(height: 8),
        _buildInfoBanner(
          'Tapping "Save Changes" will update the salon with the details above. Business hours will be converted from your local timezone ($_userTimezone) to the salon\'s timezone ($_salonTimezone).',
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
          'Edit your salon\'s core details and how customers can reach you.',
        ),
        _buildCoverSection(),
        Transform.translate(
          offset: const Offset(16, -40),
          child:
              Align(alignment: Alignment.topLeft, child: _buildLogoSeparate()),
        ),
        const SizedBox(height: 16),
        Card(
          color: _isDark ? const Color(0xFF1E1E1E) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      color: _isDark ? Colors.white : Colors.black87),
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      color: _isDark ? Colors.white : Colors.black87),
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
                      color: _isDark ? Colors.white70 : Colors.grey[500]),
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
          'Edit your working hours. Times are shown in YOUR local timezone; they will be converted to the salon\'s timezone on save.',
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
            horizontal: isMobile ? 12 : 20, vertical: isMobile ? 12 : 16),
        child: Row(
          children: [
            for (int i = 0; i < _stepMeta.length; i++) ...[
              _buildStepCircle(i, _stepMeta[i]['label'] as String,
                  _stepMeta[i]['icon'] as IconData, isMobile),
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
      int step, String label, IconData icon, bool isMobile) {
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
                  : Icon(icon,
                      size: iconSize,
                      color: isActive ? AppTheme.primary : Colors.grey[500]),
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
  // STEP ACTIONS (EDIT MODE) — lives at the bottom of the scroll
  // content (not a fixed bottomNavigationBar). Both buttons share
  // the row width via Expanded so they never overlap on mobile.
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
          title: Text(_isEditMode ? 'Edit Salon' : 'Salon Details'),
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
                    child: CircularProgressIndicator()),
                SizedBox(height: 16),
                Text('Loading salon data...'),
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
          _isEditMode ? 'Edit Salon' : 'Salon Details',
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
              tooltip: 'Delete Salon',
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
      // ✅ No fixed bottomNavigationBar anymore — the Continue/Save
      // action row now lives at the bottom of the scrollable content
      // (see _buildStepActions), so it never overlaps other content
      // on narrow/mobile screens and stays responsive.
      body: SafeArea(
        child: Container(
          color: isDark ? const Color(0xFF121212) : Colors.grey[50],
          child: Center(
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(maxWidth: isWeb ? 1000 : double.infinity),
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