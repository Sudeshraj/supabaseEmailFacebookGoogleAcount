import 'dart:io' show Platform, File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:path/path.dart' as path;
import 'package:image_cropper/image_cropper.dart';

class CreateSalonScreen extends StatefulWidget {
  const CreateSalonScreen({super.key});

  @override
  State<CreateSalonScreen> createState() => _CreateSalonScreenState();
}

class _CreateSalonScreenState extends State<CreateSalonScreen> {
  // Basic info controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Validation flags
  bool _isPhoneValid = true;
  bool _isEmailValid = true;

  // ============================================
  // GENDER SECTION - MULTI-SELECT CHIPS ONLY
  // ============================================
  List<Map<String, dynamic>> _globalGenders = [];
  final List<int> _selectedGenderIds = [];
  bool _isLoadingGenders = false;

  // ============================================
  // AGE CATEGORY SECTION - ADD WITH SUGGESTIONS
  // ============================================
  final List<Map<String, dynamic>> _addedAgeCategories = [];
  final TextEditingController _ageCategoryDisplayNameController =
      TextEditingController();
  final TextEditingController _ageCategoryMinAgeController =
      TextEditingController();
  final TextEditingController _ageCategoryMaxAgeController =
      TextEditingController();

  List<Map<String, dynamic>> _globalAgeCategories = [];
  bool _isLoadingAgeCategories = false;

  // ============================================
  // SERVICE CATEGORY SECTION - ADD WITH SUGGESTIONS
  // ============================================
  final List<Map<String, dynamic>> _addedServiceCategories = [];
  final TextEditingController _serviceCategoryNameController =
      TextEditingController();
  final TextEditingController _serviceCategoryDescriptionController =
      TextEditingController();

  String _selectedIcon = 'content_cut';
  Color _selectedColor = const Color(0xFFFF6B8B);

  List<Map<String, dynamic>> _globalCategories = [];
  bool _isLoadingCategories = false;

  // Icon list for selection
  final List<Map<String, dynamic>> _iconList = [
    {'name': 'content_cut', 'icon': Icons.content_cut, 'label': 'Scissors'},
    {'name': 'face', 'icon': Icons.face, 'label': 'Face'},
    {
      'name': 'face_retouching_natural',
      'icon': Icons.face_retouching_natural,
      'label': 'Beard',
    },
    {'name': 'spa', 'icon': Icons.spa, 'label': 'Spa'},
    {'name': 'handshake', 'icon': Icons.handshake, 'label': 'Nails'},
    {'name': 'build', 'icon': Icons.build, 'label': 'Tools'},
    {'name': 'cut', 'icon': Icons.cut, 'label': 'Hair Cut'},
    {'name': 'shower', 'icon': Icons.shower, 'label': 'Shower'},
    {'name': 'masks', 'icon': Icons.masks, 'label': 'Masks'},
    {'name': 'palette', 'icon': Icons.palette, 'label': 'Makeup'},
    {'name': 'spa_outlined', 'icon': Icons.spa_outlined, 'label': 'Wellness'},
  ];

  // Images
  File? _logoFile;
  Uint8List? _logoWebBytes;
  File? _coverFile;
  Uint8List? _coverWebBytes;
  bool _isUploadingLogo = false;
  bool _isUploadingCover = false;

  // Business hours
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;

  bool _isLoading = false;

  final _formKey = GlobalKey<FormState>();
  bool get _isWeb => MediaQuery.of(context).size.width > 800;

  final supabase = Supabase.instance.client;
  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _openTime = const TimeOfDay(hour: 9, minute: 0);
    _closeTime = const TimeOfDay(hour: 18, minute: 0);

    _ageCategoryMinAgeController.text = '0';
    _ageCategoryMaxAgeController.text = '100';

    _loadGlobalData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();

    _ageCategoryDisplayNameController.dispose();
    _ageCategoryMinAgeController.dispose();
    _ageCategoryMaxAgeController.dispose();

    _serviceCategoryNameController.dispose();
    _serviceCategoryDescriptionController.dispose();

    super.dispose();
  }

  Future<void> _loadGlobalData() async {
    setState(() {
      _isLoadingGenders = true;
      _isLoadingAgeCategories = true;
      _isLoadingCategories = true;
    });

    try {
      final genders = await supabase
          .from('genders')
          .select('id, display_name, display_order')
          .eq('is_active', true)
          .order('display_order');

      final ageCategories = await supabase
          .from('age_categories')
          .select('display_name, min_age, max_age, display_order')
          .eq('is_active', true)
          .order('display_order');

      final categories = await supabase
          .from('categories')
          .select('name, description, icon_name, color, display_order')
          .eq('is_active', true)
          .order('display_order');

      setState(() {
        _globalGenders = List<Map<String, dynamic>>.from(genders);
        _globalAgeCategories = List<Map<String, dynamic>>.from(ageCategories);
        _globalCategories = List<Map<String, dynamic>>.from(categories);
        _isLoadingGenders = false;
        _isLoadingAgeCategories = false;
        _isLoadingCategories = false;
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
      setState(() {
        _isLoadingGenders = false;
        _isLoadingAgeCategories = false;
        _isLoadingCategories = false;
      });
    }
  }

  // ============================================
  // VALIDATION FUNCTIONS
  // ============================================

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

  // ============================================
  // AGE CATEGORY FUNCTIONS
  // ============================================

  void _autoFillAgeCategory(Map<String, dynamic> selected) {
    setState(() {
      _ageCategoryDisplayNameController.text =
          selected['display_name']?.toString() ?? '';
      _ageCategoryMinAgeController.text = (selected['min_age'] ?? 0).toString();
      _ageCategoryMaxAgeController.text = (selected['max_age'] ?? 100)
          .toString();
    });
  }

  void _addAgeCategory() {
    final displayName = _ageCategoryDisplayNameController.text.trim();
    final minAge = int.tryParse(_ageCategoryMinAgeController.text.trim());
    final maxAge = int.tryParse(_ageCategoryMaxAgeController.text.trim());

    if (displayName.isEmpty) {
      _showSnackBar('Age category display name is required', Colors.orange);
      return;
    }
    if (minAge == null || maxAge == null) {
      _showSnackBar('Valid age range is required', Colors.orange);
      return;
    }
    if (minAge > maxAge) {
      _showSnackBar('Min age cannot be greater than max age', Colors.orange);
      return;
    }
    if (_addedAgeCategories.any((a) => a['display_name'] == displayName)) {
      _showSnackBar('This age category is already added', Colors.orange);
      return;
    }

    setState(() {
      _addedAgeCategories.add({
        'display_name': displayName,
        'min_age': minAge,
        'max_age': maxAge,
        'display_order': _addedAgeCategories.length,
        'is_active': true,
      });
      _ageCategoryDisplayNameController.clear();
      _ageCategoryMinAgeController.text = '0';
      _ageCategoryMaxAgeController.text = '100';
    });
    _showSnackBar('Age category added', Colors.green);
  }

  void _removeAgeCategory(int index) {
    setState(() => _addedAgeCategories.removeAt(index));
    for (int i = 0; i < _addedAgeCategories.length; i++) {
      _addedAgeCategories[i]['display_order'] = i;
    }
  }

  // ============================================
  // SERVICE CATEGORY FUNCTIONS
  // ============================================

  void _autoFillServiceCategory(Map<String, dynamic> selected) {
    setState(() {
      _serviceCategoryNameController.text = selected['name']?.toString() ?? '';
      _serviceCategoryDescriptionController.text =
          selected['description']?.toString() ?? '';
      _selectedIcon = selected['icon_name']?.toString() ?? 'content_cut';

      // Handle color properly from database
      String colorStr = selected['color']?.toString() ?? '#FF6B8B';
      if (colorStr.startsWith('#')) {
        // Remove # and parse hex
        String hex = colorStr.substring(1);
        _selectedColor = Color(int.parse('0xFF$hex'));
      } else {
        _selectedColor = const Color(0xFFFF6B8B);
      }
    });
  }

  void _addServiceCategory() {
    final name = _serviceCategoryNameController.text.trim();
    if (name.isEmpty) {
      _showSnackBar('Service category name is required', Colors.orange);
      return;
    }
    if (_addedServiceCategories.any((c) => c['name'] == name)) {
      _showSnackBar('This service category is already added', Colors.orange);
      return;
    }

    setState(() {
      _addedServiceCategories.add({
        'name': name,
        'description': _serviceCategoryDescriptionController.text.trim(),
        'icon_name': _selectedIcon,
        'color': '#${_selectedColor.toARGB32().toRadixString(16).substring(2)}',
        'display_order': _addedServiceCategories.length,
        'is_active': true,
      });
      _serviceCategoryNameController.clear();
      _serviceCategoryDescriptionController.clear();
    });
    _showSnackBar('Service category added', Colors.green);
  }

  void _removeServiceCategory(int index) {
    setState(() => _addedServiceCategories.removeAt(index));
    for (int i = 0; i < _addedServiceCategories.length; i++) {
      _addedServiceCategories[i]['display_order'] = i;
    }
  }

  // ============================================
  // CREATE SALON - ONLY SELECTED/ADDED DATA SAVED
  // ============================================

  Future<void> _createSalon() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate phone and email
    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty) {
      final cleaned = phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleaned.length < 9 ||
          cleaned.length > 10 ||
          !cleaned.startsWith('0')) {
        _showSnackBar('Please enter a valid phone number', Colors.orange);
        return;
      }
    }

    final email = _emailController.text.trim();
    if (email.isNotEmpty) {
      final emailRegex = RegExp(
        r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
      );
      if (!emailRegex.hasMatch(email)) {
        _showSnackBar('Please enter a valid email address', Colors.orange);
        return;
      }
    }

    // Validate selections and additions
    if (_selectedGenderIds.isEmpty) {
      _showSnackBar('Please select at least one gender', Colors.orange);
      return;
    }
    if (_addedAgeCategories.isEmpty) {
      _showSnackBar('Please add at least one age category', Colors.orange);
      return;
    }
    if (_addedServiceCategories.isEmpty) {
      _showSnackBar('Please add at least one service category', Colors.orange);
      return;
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnackBar('Please login first', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? logoUrl = (_logoFile != null || _logoWebBytes != null)
          ? await _uploadLogo()
          : null;
      String? coverUrl = (_coverFile != null || _coverWebBytes != null)
          ? await _uploadCover()
          : null;

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
        'logo_url': logoUrl,
        'cover_url': coverUrl,
        'open_time': _formatTimeOfDay(_openTime!),
        'close_time': _formatTimeOfDay(_closeTime!),
        'extra_data': {
          'created_from': _isWeb ? 'web' : 'mobile',
          'platform': _getPlatformName(),
        },
        'is_active': true,
      };

      final response = await supabase
          .from('salons')
          .insert(salonData)
          .select('id, name')
          .single();
      final salonId = response['id'] as int;

      // ============================================
      // SAVE ONLY SELECTED GENDERS (from chips)
      // ============================================
      // First, delete any existing (just in case)
      await supabase.from('salon_genders').delete().eq('salon_id', salonId);

      // Then save only selected genders
      for (int i = 0; i < _selectedGenderIds.length; i++) {
        final genderId = _selectedGenderIds[i];
        final gender = _globalGenders.firstWhere((g) => g['id'] == genderId);

        await supabase.from('salon_genders').insert({
          'salon_id': salonId,
          'display_name': gender['display_name'],
          'display_order': i,
          'is_active': true,
        });
      }

      // ============================================
      // SAVE ONLY ADDED AGE CATEGORIES
      // ============================================
      await supabase
          .from('salon_age_categories')
          .delete()
          .eq('salon_id', salonId);

      for (var ageCat in _addedAgeCategories) {
        await supabase.from('salon_age_categories').insert({
          'salon_id': salonId,
          'display_name': ageCat['display_name'],
          'min_age': ageCat['min_age'],
          'max_age': ageCat['max_age'],
          'display_order': ageCat['display_order'],
          'is_active': ageCat['is_active'],
        });
      }

      // ============================================
      // SAVE ONLY ADDED SERVICE CATEGORIES
      // ============================================
      await supabase.from('salon_categories').delete().eq('salon_id', salonId);

      for (var serviceCat in _addedServiceCategories) {
        await supabase.from('salon_categories').insert({
          'salon_id': salonId,
          'display_name': serviceCat['name'],
          'description': serviceCat['description'],
          'icon_name': serviceCat['icon_name'],
          'color': serviceCat['color'],
          'display_order': serviceCat['display_order'],
          'is_active': serviceCat['is_active'],
        });
      }

      if (!mounted) return;

      await showCustomAlert(
        context: context,
        title: "🎉 Salon Created!",
        message:
            "${_nameController.text.trim()} created successfully.\n\n"
            "✅ ${_selectedGenderIds.length} genders selected\n"
            "✅ ${_addedAgeCategories.length} age categories added\n"
            "✅ ${_addedServiceCategories.length} service categories added\n\n"
            "Only selected/added data has been saved.",
        isError: false,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================
  // IMAGE FUNCTIONS (Keep as before)
  // ============================================

  Future<void> _pickLogo() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _logoWebBytes = bytes;
            _logoFile = null;
          });
          _showSnackBar('Logo added successfully', Colors.green);
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Logo',
                toolbarColor: const Color(0xFFFF6B8B),
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.square,
                lockAspectRatio: true,
              ),
              IOSUiSettings(title: 'Crop Logo', aspectRatioLockEnabled: true),
            ],
          );

          if (croppedFile != null) {
            setState(() {
              _logoFile = File(croppedFile.path);
              _logoWebBytes = null;
            });
            _showSnackBar('Logo added and cropped', Colors.green);
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking logo: $e');
      _showSnackBar('Error picking logo', Colors.red);
    }
  }

  Future<void> _takeLogoPhoto() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _logoWebBytes = bytes;
            _logoFile = null;
          });
          _showSnackBar('Logo captured', Colors.green);
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Logo',
                toolbarColor: const Color(0xFFFF6B8B),
                toolbarWidgetColor: Colors.white,
                lockAspectRatio: true,
              ),
              IOSUiSettings(title: 'Crop Logo', aspectRatioLockEnabled: true),
            ],
          );

          if (croppedFile != null) {
            setState(() {
              _logoFile = File(croppedFile.path);
              _logoWebBytes = null;
            });
            _showSnackBar('Logo captured and cropped', Colors.green);
          }
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
      _showSnackBar('Error taking photo', Colors.red);
    }
  }

  void _removeLogo() {
    setState(() {
      _logoFile = null;
      _logoWebBytes = null;
    });
    _showSnackBar('Logo removed', Colors.red);
  }

  Future<void> _pickCover() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _coverWebBytes = bytes;
            _coverFile = null;
          });
          _showSnackBar('Cover photo added successfully', Colors.green);
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Cover',
                toolbarColor: const Color(0xFFFF6B8B),
                toolbarWidgetColor: Colors.white,
                initAspectRatio: CropAspectRatioPreset.ratio16x9,
                lockAspectRatio: true,
              ),
              IOSUiSettings(title: 'Crop Cover', aspectRatioLockEnabled: true),
            ],
          );

          if (croppedFile != null) {
            setState(() {
              _coverFile = File(croppedFile.path);
              _coverWebBytes = null;
            });
            _showSnackBar('Cover photo added and cropped', Colors.green);
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking cover: $e');
      _showSnackBar('Error picking cover', Colors.red);
    }
  }

  Future<void> _takeCoverPhoto() async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _coverWebBytes = bytes;
            _coverFile = null;
          });
          _showSnackBar('Cover captured', Colors.green);
        } else {
          final croppedFile = await ImageCropper().cropImage(
            sourcePath: pickedFile.path,
            aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
            uiSettings: [
              AndroidUiSettings(
                toolbarTitle: 'Crop Cover',
                toolbarColor: const Color(0xFFFF6B8B),
                toolbarWidgetColor: Colors.white,
                lockAspectRatio: true,
              ),
              IOSUiSettings(title: 'Crop Cover', aspectRatioLockEnabled: true),
            ],
          );

          if (croppedFile != null) {
            setState(() {
              _coverFile = File(croppedFile.path);
              _coverWebBytes = null;
            });
            _showSnackBar('Cover captured and cropped', Colors.green);
          }
        }
      }
    } catch (e) {
      debugPrint('Error: $e');
      _showSnackBar('Error taking photo', Colors.red);
    }
  }

  void _removeCover() {
    setState(() {
      _coverFile = null;
      _coverWebBytes = null;
    });
    _showSnackBar('Cover photo removed', Colors.red);
  }

  // ============================================
  // UI WIDGETS
  // ============================================

  Widget _buildCoverSection() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

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
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
                image: (_coverFile != null || _coverWebBytes != null)
                    ? DecorationImage(
                        image: kIsWeb && _coverWebBytes != null
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
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to add cover photo',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: isDesktop ? 14 : 12,
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
                    children: [
                      const Icon(Icons.edit, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    return Container(
      margin: const EdgeInsets.only(left: 16, top: 0, bottom: 16),
      child: GestureDetector(
        onTap: () => _showLogoSourceDialog(),
        child: Container(
          width: isDesktop ? 100 : 80,
          height: isDesktop ? 100 : 80,
          decoration: BoxDecoration(
            color: Colors.white,
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
                    image: kIsWeb && _logoWebBytes != null
                        ? MemoryImage(_logoWebBytes!)
                        : FileImage(_logoFile!) as ImageProvider,
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: (_logoFile == null && _logoWebBytes == null)
              ? Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_a_photo,
                        size: isDesktop ? 30 : 24,
                        color: Colors.grey[600],
                      ),
                      SizedBox(height: isDesktop ? 4 : 2),
                      Text(
                        'Add Logo',
                        style: TextStyle(
                          fontSize: isDesktop ? 10 : 8,
                          color: Colors.grey[600],
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
                          color: const Color(0xFFFF6B8B),
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Add Logo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: Color(0xFFFF6B8B),
              ),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickLogo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFFF6B8B)),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _takeLogoPhoto();
              },
            ),
            if (_logoFile != null || _logoWebBytes != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove Logo',
                  style: TextStyle(color: Colors.red),
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
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Add Cover Photo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: Color(0xFFFF6B8B),
              ),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickCover();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFFF6B8B)),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _takeCoverPhoto();
              },
            ),
            if (_coverFile != null || _coverWebBytes != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove Cover',
                  style: TextStyle(color: Colors.red),
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
  // GENDER SECTION - MULTI-SELECT CHIPS ONLY
  // ============================================

  Widget _buildGenderSelection() {
    if (_isLoadingGenders) {
      return _buildLoadingCard('Genders', Icons.people, Colors.blue);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
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
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.people, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Select Genders',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_selectedGenderIds.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedGenderIds.clear();
                      });
                    },
                    child: const Text(
                      'Clear All',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Select the genders your salon serves',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(_globalGenders.length, (index) {
                final gender = _globalGenders[index];
                final id = gender['id'] as int;
                final isSelected = _selectedGenderIds.contains(id);
                final displayName = gender['display_name'] as String;

                return FilterChip(
                  label: Text(displayName),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedGenderIds.add(id);
                      } else {
                        _selectedGenderIds.remove(id);
                      }
                    });
                  },
                  backgroundColor: Colors.white,
                  selectedColor: Colors.blue.withValues(alpha: 0.2),
                  checkmarkColor: Colors.blue,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.blue : Colors.grey[700],
                    fontWeight: isSelected
                        ? FontWeight.w500
                        : FontWeight.normal,
                  ),
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: isSelected ? Colors.blue : Colors.grey[300]!,
                    ),
                  ),
                );
              }),
            ),
            if (_selectedGenderIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_selectedGenderIds.length} gender${_selectedGenderIds.length > 1 ? 's' : ''} selected',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // AGE CATEGORY SECTION - ADD WITH SUGGESTIONS
  // ============================================

  Widget _buildAgeCategorySection() {
    return _buildAddableSection(
      title: 'Age Categories',
      icon: Icons.calendar_today,
      color: Colors.green,
      isLoading: _isLoadingAgeCategories,
      addedItems: _addedAgeCategories,
      onRemove: _removeAgeCategory,
      itemDisplayName: (item) =>
          '${item['display_name']} (${item['min_age']}-${item['max_age']})',
      formFields: [
        _buildSuggestionField(
          controller: _ageCategoryDisplayNameController,
          label: 'Display Name *',
          hint: 'e.g., Child, Teen, Adult, Senior',
          icon: Icons.visibility,
          suggestions: _globalAgeCategories
              .map((a) => a['display_name'] as String)
              .toList(),
          onSelected: (String value) {
            final selected = _globalAgeCategories.firstWhere(
              (a) => a['display_name'] == value,
              orElse: () => {},
            );
            if (selected.isNotEmpty) {
              _autoFillAgeCategory(selected);
            }
          },
        ),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _ageCategoryMinAgeController,
                label: 'Min Age',
                hint: '0',
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildTextField(
                controller: _ageCategoryMaxAgeController,
                label: 'Max Age',
                hint: '100',
                icon: Icons.numbers,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
      ],
      onAdd: _addAgeCategory,
    );
  }

  // ============================================
  // SERVICE CATEGORY SECTION - ADD WITH SUGGESTIONS
  // ============================================

  Widget _buildServiceCategorySection() {
    return _buildAddableSection(
      title: 'Service Categories',
      icon: Icons.category,
      color: Colors.orange,
      isLoading: _isLoadingCategories,
      addedItems: _addedServiceCategories,
      onRemove: _removeServiceCategory,
      itemDisplayName: (item) => item['name'],
      formFields: [
        _buildSuggestionField(
          controller: _serviceCategoryNameController,
          label: 'Name *',
          hint: 'e.g., hair, skin, nails',
          icon: Icons.category,
          suggestions: _globalCategories
              .map((c) => c['name'] as String)
              .toList(),
          onSelected: (String value) {
            final selected = _globalCategories.firstWhere(
              (c) => c['name'] == value,
              orElse: () => {},
            );
            if (selected.isNotEmpty) {
              _autoFillServiceCategory(selected);
            }
          },
        ),
        _buildTextField(
          controller: _serviceCategoryDescriptionController,
          label: 'Description',
          hint: 'e.g., Hair cutting and styling services',
          icon: Icons.description,
          maxLines: 2,
        ),
        _buildIconSelector(),
        const SizedBox(height: 12),
        _buildColorPicker(),
      ],
      onAdd: _addServiceCategory,
    );
  }

  Widget _buildLoadingCard(String title, IconData icon, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddableSection({
    required String title,
    required IconData icon,
    required Color color,
    required bool isLoading,
    required List<Map<String, dynamic>> addedItems,
    required Function(int) onRemove,
    required String Function(Map<String, dynamic>) itemDisplayName,
    required List<Widget> formFields,
    required VoidCallback onAdd,
  }) {
    if (isLoading) {
      return _buildLoadingCard(title, icon, color);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text('${addedItems.length} items added'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...formFields,
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onAdd,
                    icon: const Icon(Icons.add),
                    label: Text('Add $title'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (addedItems.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Added Items:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: addedItems.length,
                    itemBuilder: (context, index) {
                      final item = addedItems[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        ),
                        title: Text(itemDisplayName(item)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => onRemove(index),
                        ),
                        dense: true,
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconSelector() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    // Dynamic column count based on screen width
    int getColumns() {
      if (screenWidth > 1200) return 10;
      if (screenWidth > 1000) return 9;
      if (screenWidth > 800) return 8;
      return 6; // Tablet fallback
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Icon',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _iconList.length.toString(),
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFFF6B8B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (isDesktop)
          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = getColumns();

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 0.9,
                ),
                itemCount: _iconList.length,
                itemBuilder: (context, index) {
                  final iconItem = _iconList[index];
                  final isSelected = _selectedIcon == iconItem['name'];

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedIcon = iconItem['name'] as String;
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFF6B8B).withValues(alpha: 0.1)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFFF6B8B)
                              : Colors.grey[300]!,
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            iconItem['icon'] as IconData,
                            size: 18,
                            color: isSelected
                                ? const Color(0xFFFF6B8B)
                                : Colors.grey[600],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            iconItem['label'] as String,
                            style: TextStyle(
                              fontSize: 9,
                              color: isSelected
                                  ? const Color(0xFFFF6B8B)
                                  : Colors.grey[600],
                              fontWeight: isSelected
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          )
        else
          // Mobile View - Same as before
          SizedBox(
            height: 70,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _iconList.length,
              itemBuilder: (context, index) {
                final iconItem = _iconList[index];
                final isSelected = _selectedIcon == iconItem['name'];

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedIcon = iconItem['name'] as String;
                    });
                  },
                  child: Container(
                    width: 65,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFFF6B8B).withValues(alpha: 0.1)
                          : Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFFFF6B8B)
                            : Colors.grey[300]!,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          iconItem['icon'] as IconData,
                          size: 24,
                          color: isSelected
                              ? const Color(0xFFFF6B8B)
                              : Colors.grey[600],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          iconItem['label'] as String,
                          style: TextStyle(
                            fontSize: 9,
                            color: isSelected
                                ? const Color(0xFFFF6B8B)
                                : Colors.grey[600],
                            fontWeight: isSelected
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildColorPicker() {
    final List<Color> colorOptions = [
      const Color(0xFFFF6B8B), // Pink
      const Color(0xFF4CAF50), // Green
      const Color(0xFF2196F3), // Blue
      const Color(0xFFFF9800), // Orange
      const Color(0xFF9C27B0), // Purple
      const Color(0xFFF44336), // Red
      const Color(0xFF00BCD4), // Cyan
      const Color(0xFF795548), // Brown
      const Color(0xFF607D8B), // Blue Grey
      const Color(0xFFE91E63), // Pink
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Color',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: colorOptions.map((color) {
            final isSelected = _selectedColor == color;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedColor = color;
                });
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? const Center(
                        child: Icon(Icons.check, color: Colors.white, size: 20),
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSuggestionField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required List<String> suggestions,
    required Function(String) onSelected,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Autocomplete<String>(
        optionsBuilder: (TextEditingValue textEditingValue) {
          if (textEditingValue.text.isEmpty) {
            return const Iterable<String>.empty();
          }
          return suggestions.where(
            (option) => option.toLowerCase().contains(
              textEditingValue.text.toLowerCase(),
            ),
          );
        },
        onSelected: (String selection) {
          onSelected(selection);
          controller.text = selection;
        },
        fieldViewBuilder:
            (context, textController, focusNode, onFieldSubmitted) {
              if (textController.text != controller.text) {
                textController.text = controller.text;
              }
              controller.addListener(() {
                if (textController.text != controller.text) {
                  textController.text = controller.text;
                }
              });

              return TextFormField(
                controller: textController,
                focusNode: focusNode,
                keyboardType: keyboardType,
                maxLines: maxLines,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  prefixIcon: Icon(icon, color: Colors.grey),
                  suffixIcon: const Icon(
                    Icons.arrow_drop_down,
                    color: Colors.grey,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFFFF6B8B),
                      width: 2,
                    ),
                  ),
                ),
                onChanged: (value) => controller.text = value,
              );
            },
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: (value) {
          if (isPhone) {
            _validatePhone(value);
          }
          if (isEmail) {
            _validateEmail(value);
          }
        },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.grey),
          errorText: isPhone && !_isPhoneValid && controller.text.isNotEmpty
              ? 'Enter valid phone number (e.g., 0771234567)'
              : isEmail && !_isEmailValid && controller.text.isNotEmpty
              ? 'Enter valid email address'
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.red, width: 2),
          ),
        ),
      ),
    );
  }

  // Helper methods
  Future<String?> _uploadLogo() async {
    if (_logoFile == null && _logoWebBytes == null) return null;
    setState(() => _isUploadingLogo = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');
      String fileName;
      if (kIsWeb && _logoWebBytes != null) {
        fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}.png';
        final filePath = 'salons/$userId/$fileName';
        await supabase.storage
            .from('salon-images')
            .uploadBinary(filePath, _logoWebBytes!);
        return supabase.storage.from('salon-images').getPublicUrl(filePath);
      } else if (_logoFile != null) {
        final fileExt = path.extension(_logoFile!.path);
        fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}$fileExt';
        final filePath = 'salons/$userId/$fileName';
        await supabase.storage
            .from('salon-images')
            .upload(filePath, _logoFile!);
        return supabase.storage.from('salon-images').getPublicUrl(filePath);
      }
      return null;
    } catch (e) {
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  Future<String?> _uploadCover() async {
    if (_coverFile == null && _coverWebBytes == null) return null;
    setState(() => _isUploadingCover = true);
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Not logged in');
      String fileName;
      if (kIsWeb && _coverWebBytes != null) {
        fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}.png';
        final filePath = 'salons/$userId/$fileName';
        await supabase.storage
            .from('salon-images')
            .uploadBinary(filePath, _coverWebBytes!);
        return supabase.storage.from('salon-images').getPublicUrl(filePath);
      } else if (_coverFile != null) {
        final fileExt = path.extension(_coverFile!.path);
        fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}$fileExt';
        final filePath = 'salons/$userId/$fileName';
        await supabase.storage
            .from('salon-images')
            .upload(filePath, _coverFile!);
        return supabase.storage.from('salon-images').getPublicUrl(filePath);
      }
      return null;
    } catch (e) {
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingCover = false);
    }
  }

  String _formatTimeOfDay(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
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

  Future<void> _selectTime(BuildContext context, bool isOpen) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isOpen ? _openTime! : _closeTime!,
    );
    if (picked != null) {
      setState(() => isOpen ? _openTime = picked : _closeTime = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Salon'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isDesktop,
      ),
      body: Container(
        color: Colors.grey[50],
        child: Center(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 1000 : double.infinity,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(isDesktop ? 32 : 16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Cover Section
                    _buildCoverSection(),

                    // Logo Section
                    Transform.translate(
                      offset: const Offset(16, -40),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: _buildLogoSeparate(),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Basic Info Card
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Basic Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
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

                    // Contact Info Card with Validation
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Contact Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
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
                              hint:
                                  'Enter email address (e.g., salon@example.com)',
                              icon: Icons.email,
                              keyboardType: TextInputType.emailAddress,
                              isEmail: true,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Phone and email are optional but recommended for customer contact',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Business Hours Card
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Business Hours',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildTimeTile(
                                    'Open Time',
                                    _openTime!,
                                    Icons.access_time,
                                    () => _selectTime(context, true),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildTimeTile(
                                    'Close Time',
                                    _closeTime!,
                                    Icons.access_time,
                                    () => _selectTime(context, false),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Service Categories Section (Add with Suggestions)
                    _buildServiceCategorySection(),

                    // Age Categories Section (Add with Suggestions)
                    _buildAgeCategorySection(),

                    // Genders Section (Multi-Select Chips Only)
                    _buildGenderSelection(),

                    const SizedBox(height: 24),

                    // Create Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed:
                            (_isLoading ||
                                _isUploadingLogo ||
                                _isUploadingCover)
                            ? null
                            : _createSalon,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B8B),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child:
                            _isLoading || _isUploadingLogo || _isUploadingCover
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _isUploadingLogo || _isUploadingCover
                                        ? 'Uploading...'
                                        : 'Creating...',
                                  ),
                                ],
                              )
                            : const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add_business, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Create Salon',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
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
    );
  }

  Widget _buildTimeTile(
    String label,
    TimeOfDay time,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[400]!),
          borderRadius: BorderRadius.circular(12),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                Text(
                  time.format(context),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
