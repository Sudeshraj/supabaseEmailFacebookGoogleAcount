import 'dart:io' show Platform, File; // Only for mobile
import 'dart:typed_data'; // For web
import 'package:flutter/foundation.dart' show kIsWeb; // Web check
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:path/path.dart' as path;

class CreateSalonScreen extends StatefulWidget {
  const CreateSalonScreen({super.key});

  @override
  State<CreateSalonScreen> createState() => _CreateSalonScreenState();
}

class _CreateSalonScreenState extends State<CreateSalonScreen> {
  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Images - handle both mobile and web
  File? _logoFile;  // For mobile
  Uint8List? _logoWebBytes; // For web
  File? _coverFile; // For mobile
  Uint8List? _coverWebBytes; // For web
  
  String? _logoUrl;
  String? _coverUrl;
  
  bool _isUploadingLogo = false;
  bool _isUploadingCover = false;

  // Business hours
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;

  // Loading state
  bool _isLoading = false;

  // Form key
  final _formKey = GlobalKey<FormState>();

  // Responsive layout helpers
  bool get _isWeb => MediaQuery.of(context).size.width > 800;
  bool get _isTablet =>
      MediaQuery.of(context).size.width > 600 &&
      MediaQuery.of(context).size.width <= 800;

  final supabase = Supabase.instance.client;
  final picker = ImagePicker();

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Set default business hours
    _openTime = const TimeOfDay(hour: 9, minute: 0);
    _closeTime = const TimeOfDay(hour: 18, minute: 0);
  }

  // Get platform name safely
  String _getPlatformName() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'mobile';
  }

  // 📸 Pick logo image (web compatible)
  Future<void> _pickLogoImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        if (kIsWeb) {
          // Web: read as bytes
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _logoWebBytes = bytes;
            _logoFile = null;
            _logoUrl = null;
          });
        } else {
          // Mobile: use File
          setState(() {
            _logoFile = File(pickedFile.path);
            _logoWebBytes = null;
            _logoUrl = null;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error picking logo: $e');
      if (mounted) {
        _showSnackBar('Error picking logo', Colors.red);
      }
    }
  }

  // 📸 Pick cover image (web compatible)
  Future<void> _pickCoverImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 400,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        if (kIsWeb) {
          // Web: read as bytes
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _coverWebBytes = bytes;
            _coverFile = null;
            _coverUrl = null;
          });
        } else {
          // Mobile: use File
          setState(() {
            _coverFile = File(pickedFile.path);
            _coverWebBytes = null;
            _coverUrl = null;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error picking cover: $e');
      if (mounted) {
        _showSnackBar('Error picking cover', Colors.red);
      }
    }
  }

  // Get file extension from XFile (for web)
  String _getFileExtension(XFile file) {
    try {
      final name = file.name;
      final lastDot = name.lastIndexOf('.');
      if (lastDot != -1) return name.substring(lastDot);
      return '.png';
    } catch (e) {
      return '.png';
    }
  }

  // ☁️ Upload logo to Supabase Storage (web compatible)
  Future<String?> _uploadLogo() async {
    if (_logoFile == null && _logoWebBytes == null) return null;

    setState(() {
      _isUploadingLogo = true;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not logged in');

      String fileName;
      
      if (kIsWeb && _logoWebBytes != null) {
        // Web upload
        fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}.png';
        final filePath = 'salons/$userId/$fileName';
        
        debugPrint('📤 Uploading logo to: $filePath');
        
        await supabase.storage
            .from('salon-images')
            .uploadBinary(
              filePath,
              _logoWebBytes!,
              fileOptions: const FileOptions(cacheControl: '3600'),
            );
        
        final imageUrl = supabase.storage
            .from('salon-images')
            .getPublicUrl(filePath);
        
        debugPrint('✅ Logo uploaded: $imageUrl');
        return imageUrl;
      } 
      else if (_logoFile != null) {
        // Mobile upload
        final fileExt = path.extension(_logoFile!.path);
        fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}$fileExt';
        final filePath = 'salons/$userId/$fileName';
        
        debugPrint('📤 Uploading logo to: $filePath');
        
        await supabase.storage
            .from('salon-images')
            .upload(
              filePath,
              _logoFile!,
              fileOptions: const FileOptions(cacheControl: '3600'),
            );
        
        final imageUrl = supabase.storage
            .from('salon-images')
            .getPublicUrl(filePath);
        
        debugPrint('✅ Logo uploaded: $imageUrl');
        return imageUrl;
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Error uploading logo: $e');
      if (mounted) {
        _showSnackBar('Error uploading logo', Colors.red);
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingLogo = false;
        });
      }
    }
  }

  // ☁️ Upload cover to Supabase Storage (web compatible)
  Future<String?> _uploadCover() async {
    if (_coverFile == null && _coverWebBytes == null) return null;

    setState(() {
      _isUploadingCover = true;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not logged in');

      String fileName;
      
      if (kIsWeb && _coverWebBytes != null) {
        // Web upload
        fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}.png';
        final filePath = 'salons/$userId/$fileName';
        
        debugPrint('📤 Uploading cover to: $filePath');
        
        await supabase.storage
            .from('salon-images')
            .uploadBinary(
              filePath,
              _coverWebBytes!,
              fileOptions: const FileOptions(cacheControl: '3600'),
            );
        
        final imageUrl = supabase.storage
            .from('salon-images')
            .getPublicUrl(filePath);
        
        debugPrint('✅ Cover uploaded: $imageUrl');
        return imageUrl;
      } 
      else if (_coverFile != null) {
        // Mobile upload
        final fileExt = path.extension(_coverFile!.path);
        fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}$fileExt';
        final filePath = 'salons/$userId/$fileName';
        
        debugPrint('📤 Uploading cover to: $filePath');
        
        await supabase.storage
            .from('salon-images')
            .upload(
              filePath,
              _coverFile!,
              fileOptions: const FileOptions(cacheControl: '3600'),
            );
        
        final imageUrl = supabase.storage
            .from('salon-images')
            .getPublicUrl(filePath);
        
        debugPrint('✅ Cover uploaded: $imageUrl');
        return imageUrl;
      }
      
      return null;
    } catch (e) {
      debugPrint('❌ Error uploading cover: $e');
      if (mounted) {
        _showSnackBar('Error uploading cover', Colors.red);
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingCover = false;
        });
      }
    }
  }

  // 🕒 Select time
  Future<void> _selectTime(BuildContext context, bool isOpenTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isOpenTime ? _openTime! : _closeTime!,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFF6B8B),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isOpenTime) {
          _openTime = picked;
        } else {
          _closeTime = picked;
        }
      });
    }
  }

  // 💾 Create salon in database
  Future<void> _createSalon() async {
    if (!_formKey.currentState!.validate()) return;

    // Check if user is logged in
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnackBar('Please login first', Colors.red);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Upload images first if selected
      String? logoUrl;
      if (_logoFile != null || _logoWebBytes != null) {
        logoUrl = await _uploadLogo();
      }

      String? coverUrl;
      if (_coverFile != null || _coverWebBytes != null) {
        coverUrl = await _uploadCover();
      }

      // Prepare salon data
      final salonData = {
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim().isNotEmpty
            ? _addressController.text.trim()
            : null,
        'phone': _phoneController.text.trim().isNotEmpty
            ? _phoneController.text.trim()
            : null,
        'email': _emailController.text.trim().isNotEmpty
            ? _emailController.text.trim()
            : null,
        'owner_id': userId,
        'description': _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        'logo_url': logoUrl,
        'cover_url': coverUrl,
        'open_time': '${_openTime!.hour.toString().padLeft(2, '0')}:${_openTime!.minute.toString().padLeft(2, '0')}:00',
        'close_time': '${_closeTime!.hour.toString().padLeft(2, '0')}:${_closeTime!.minute.toString().padLeft(2, '0')}:00',
        'extra_data': {
          'created_from': _isWeb ? 'web' : 'mobile',
          'platform': _getPlatformName(),
        },
        'is_active': true,
      };

      debugPrint('📝 Creating salon: ${_nameController.text.trim()}');

      final response = await supabase
          .from('salons')
          .insert(salonData)
          .select('id, name')
          .single();

      debugPrint('✅ Salon created: ${response['id']}');

      if (mounted) {
        await showCustomAlert(
          context: context,
          title: "🎉 Salon Created!",
          message:
              "${_nameController.text.trim()} has been created successfully.\n\n"
              "You can now add genders, categories, and age categories from the salon management screen.",
          isError: false,
        );

        if (context.mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      debugPrint('❌ Error creating salon: $e');
      if (mounted) {
        _showSnackBar('Error creating salon', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // Helper to get logo image provider
  ImageProvider _getLogoImage() {
    if (kIsWeb && _logoWebBytes != null) {
      return MemoryImage(_logoWebBytes!);
    } else if (_logoFile != null) {
      return FileImage(_logoFile!);
    } else if (_logoUrl != null) {
      return NetworkImage(_logoUrl!);
    }
    return const AssetImage(''); // Empty placeholder
  }

  // Helper to get cover image provider
  ImageProvider _getCoverImage() {
    if (kIsWeb && _coverWebBytes != null) {
      return MemoryImage(_coverWebBytes!);
    } else if (_coverFile != null) {
      return FileImage(_coverFile!);
    } else if (_coverUrl != null) {
      return NetworkImage(_coverUrl!);
    }
    return const AssetImage(''); // Empty placeholder
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Salon'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: _isWeb,
        elevation: 0,
      ),
      body: Container(
        color: Colors.grey[50],
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _isWeb ? 1000 : double.infinity,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(_isWeb ? 32 : 16),
              child: Card(
                elevation: _isWeb ? 4 : 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: EdgeInsets.all(_isWeb ? 32 : 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        _buildHeader(),

                        const SizedBox(height: 32),

                        // Cover Image Section
                        _buildCoverImageSection(),

                        const SizedBox(height: 24),

                        // Logo and Basic Info Row
                        _isWeb 
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Logo Section
                                  Expanded(flex: 1, child: _buildLogoSection()),
                                  const SizedBox(width: 24),
                                  // Basic Info
                                  Expanded(flex: 2, child: _buildBasicInfoFields()),
                                ],
                              )
                            : Column(
                                children: [
                                  _buildLogoSection(),
                                  const SizedBox(height: 24),
                                  _buildBasicInfoFields(),
                                ],
                              ),

                        const SizedBox(height: 24),

                        // Business Hours
                        _buildBusinessHoursSection(),

                        const SizedBox(height: 24),

                        // Contact Information
                        _buildContactSection(),

                        const SizedBox(height: 24),

                        // Description
                        _buildDescriptionField(),

                        const SizedBox(height: 32),

                        // Create Button
                        _buildCreateButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Header (same as before)
  Widget _buildHeader() {
    return Center(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.store,
              color: Color(0xFFFF6B8B),
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Create Your Salon',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Fill in the details below to create your salon',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Cover Image Section (updated for web)
  Widget _buildCoverImageSection() {
    bool hasCover = (kIsWeb && _coverWebBytes != null) || _coverFile != null || _coverUrl != null;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cover Image',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Upload a cover photo for your salon (recommended size: 1200x400)',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),

        GestureDetector(
          onTap: _isUploadingCover ? null : () => _showCoverImageSourceDialog(),
          child: Container(
            width: double.infinity,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!, width: 1),
            ),
            child: hasCover
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: kIsWeb && _coverWebBytes != null
                            ? Image.memory(
                                _coverWebBytes!,
                                fit: BoxFit.cover,
                              )
                            : _coverFile != null
                                ? Image.file(
                                    _coverFile!,
                                    fit: BoxFit.cover,
                                  )
                                : Image.network(
                                    _coverUrl!,
                                    fit: BoxFit.cover,
                                  ),
                      ),
                      if (_isUploadingCover)
                        Positioned.fill(
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.5),
                            child: const Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFFFF6B8B),
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFFFF6B8B),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: _isUploadingCover
                                ? null
                                : _showCoverImageSourceDialog,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate,
                        size: 40,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Add Cover Photo',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // Logo Section (updated for web)
  Widget _buildLogoSection() {
    bool hasLogo = (kIsWeb && _logoWebBytes != null) || _logoFile != null || _logoUrl != null;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Logo',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Upload your salon logo (square image recommended)',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),

        Center(
          child: GestureDetector(
            onTap: _isUploadingLogo ? null : () => _showLogoImageSourceDialog(),
            child: Stack(
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(60),
                    border: Border.all(color: Colors.grey[300]!, width: 2),
                  ),
                  child: hasLogo
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(60),
                          child: kIsWeb && _logoWebBytes != null
                              ? Image.memory(
                                  _logoWebBytes!,
                                  fit: BoxFit.cover,
                                )
                              : _logoFile != null
                                  ? Image.file(
                                      _logoFile!,
                                      fit: BoxFit.cover,
                                    )
                                  : Image.network(
                                      _logoUrl!,
                                      fit: BoxFit.cover,
                                    ),
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo,
                              size: 30,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Add Logo',
                              style: TextStyle(color: Colors.grey, fontSize: 11),
                            ),
                          ],
                        ),
                ),
                if (_isUploadingLogo)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(60),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF6B8B),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Basic Info Fields (same as before)
  Widget _buildBasicInfoFields() {
    return Column(
      children: [
        // Salon Name (Required)
        const Text(
          'Salon Name *',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: 'Enter your salon name',
            prefixIcon: const Icon(Icons.store, color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Salon name is required';
            }
            return null;
          },
        ),

        const SizedBox(height: 16),

        // Address
        const Text(
          'Address',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _addressController,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: 'Enter salon address',
            prefixIcon: const Icon(Icons.location_on, color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  // Business Hours Section (same as before)
  Widget _buildBusinessHoursSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Business Hours',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTimePickerTile(
                  label: 'Open Time',
                  time: _openTime!,
                  icon: Icons.access_time,
                  onTap: () => _selectTime(context, true),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildTimePickerTile(
                  label: 'Close Time',
                  time: _closeTime!,
                  icon: Icons.access_time,
                  onTap: () => _selectTime(context, false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Time Picker Tile (same as before)
  Widget _buildTimePickerTile({
    required String label,
    required TimeOfDay time,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[400]!),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
                Text(
                  time.format(context),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Contact Section (same as before)
  Widget _buildContactSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contact Information',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        
        // Phone
        const Text(
          'Phone Number',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: 'Enter phone number',
            prefixIcon: const Icon(Icons.phone, color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Email
        const Text(
          'Email Address',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'Enter email address',
            prefixIcon: const Icon(Icons.email, color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
            ),
          ),
          validator: (value) {
            if (value != null && value.isNotEmpty) {
              if (!RegExp(
                r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
              ).hasMatch(value)) {
                return 'Enter a valid email';
              }
            }
            return null;
          },
        ),
      ],
    );
  }

  // Description Field (same as before)
  Widget _buildDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Description (Optional)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tell customers about your salon, services, and atmosphere',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _descriptionController,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Enter salon description...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  // Create Button (same as before)
  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: (_isLoading || _isUploadingLogo || _isUploadingCover) ? null : _createSalon,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isLoading || _isUploadingLogo || _isUploadingCover
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
                        ? 'Uploading images...'
                        : 'Creating...'
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }

  // Logo Image Source Dialog (same as before)
  void _showLogoImageSourceDialog() {
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
                'Select Logo Source',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFFF6B8B)),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickLogoImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFFF6B8B)),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickLogoImage(ImageSource.camera);
              },
            ),
            if (_logoFile != null || _logoWebBytes != null || _logoUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove Logo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _logoFile = null;
                    _logoWebBytes = null;
                    _logoUrl = null;
                  });
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Cover Image Source Dialog (same as before)
  void _showCoverImageSourceDialog() {
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
                'Select Cover Image Source',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFFF6B8B)),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickCoverImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFFF6B8B)),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickCoverImage(ImageSource.camera);
              },
            ),
            if (_coverFile != null || _coverWebBytes != null || _coverUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove Cover Image',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _coverFile = null;
                    _coverWebBytes = null;
                    _coverUrl = null;
                  });
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}