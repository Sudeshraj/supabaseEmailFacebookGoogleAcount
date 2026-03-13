import 'dart:io';
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

  // Image
  File? _imageFile;
  String? _imageUrl;
  bool _isUploading = false;

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

  // 📸 Pick image from gallery or camera
  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _imageUrl = null; // Clear any existing URL
        });
      }
    } catch (e) {
      debugPrint('❌ Error picking image: $e');
      if (mounted) {
        _showSnackBar('Error picking image: $e', Colors.red);
      }
    }
  }

  // ☁️ Upload image to Supabase Storage
  Future<String?> _uploadImage() async {
    if (_imageFile == null) return null;

    setState(() {
      _isUploading = true;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not logged in');

      // Create unique file name
      final fileExt = path.extension(_imageFile!.path);
      const timestamp = 'salon_';
      final fileName =
          '${timestamp}${DateTime.now().millisecondsSinceEpoch}$fileExt';
      final filePath = 'salons/$userId/$fileName';

      debugPrint('📤 Uploading image to: $filePath');

      // Upload to Supabase Storage
      await supabase.storage
          .from('salon-images')
          .upload(
            filePath,
            _imageFile!,
            fileOptions: const FileOptions(cacheControl: '3600'),
          );

      // Get public URL
      final imageUrl = supabase.storage
          .from('salon-images')
          .getPublicUrl(filePath);
      debugPrint('✅ Image uploaded: $imageUrl');

      return imageUrl;
    } catch (e) {
      debugPrint('❌ Error uploading image: $e');
      if (mounted) {
        _showSnackBar('Error uploading image: $e', Colors.red);
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
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
      // Upload image first if selected
      String? imageUrl;
      if (_imageFile != null) {
        imageUrl = await _uploadImage();
        if (imageUrl == null) {
          // Image upload failed but we can still continue without image
          _showSnackBar(
            'Image upload failed, but salon will be created without image',
            Colors.orange,
          );
        }
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
        'extra_data': {
          if (_descriptionController.text.trim().isNotEmpty)
            'description': _descriptionController.text.trim(),
          if (imageUrl != null) 'image_url': imageUrl,
          'created_from': _isWeb ? 'web' : 'mobile',
        },
        'is_active': true,
      };

      debugPrint('📝 Creating salon with data: $salonData');

      // Insert into database
      final response = await supabase
          .from('salons')
          .insert(salonData)
          .select('id, name')
          .single();

      debugPrint('✅ Salon created successfully: $response');

      // CreateSalonScreen එකේ success වුනාම
      if (mounted) {
        await showCustomAlert(
          context: context,
          title: "🎉 Salon Created!",
          message:
              "${_nameController.text.trim()} has been created successfully.",
          isError: false,
        );

        if (context.mounted) {
          // 🔥 Return true to indicate success
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      debugPrint('❌ Error creating salon: $e');
      if (mounted) {
        _showSnackBar('Error creating salon: ${e.toString()}', Colors.red);
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

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

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
              maxWidth: _isWeb ? 800 : double.infinity,
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
                        Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFFFF6B8B,
                                  ).withValues(alpha: 0.1),
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
                        ),

                        const SizedBox(height: 32),

                        // 📸 Image Upload Section
                        _buildImageUploadSection(),

                        const SizedBox(height: 24),

                        // 📝 Form Fields
                        _buildFormFields(),

                        const SizedBox(height: 32),

                        // ✅ Create Button
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

  // 📸 Image Upload Section
  Widget _buildImageUploadSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Salon Profile Image',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Upload a photo of your salon (optional)',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),

        Center(
          child: Stack(
            children: [
              // Image Preview
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey[300]!, width: 2),
                  image: _imageFile != null
                      ? DecorationImage(
                          image: FileImage(_imageFile!),
                          fit: BoxFit.cover,
                        )
                      : (_imageUrl != null
                            ? DecorationImage(
                                image: NetworkImage(_imageUrl!),
                                fit: BoxFit.cover,
                              )
                            : null),
                ),
                child: _imageFile == null && _imageUrl == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate,
                            size: 40,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Add Photo',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      )
                    : null,
              ),

              // Upload Overlay
              if (_isUploading)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFFF6B8B),
                      ),
                    ),
                  ),
                ),

              // Edit Button
              if (!_isUploading && (_imageFile != null || _imageUrl != null))
                Positioned(
                  bottom: 5,
                  right: 5,
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
                      onPressed: _showImageSourceDialog,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // 📝 Form Fields
  Widget _buildFormFields() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          maxLines: isSmallScreen ? 2 : 3,
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

        const SizedBox(height: 16),

        // Phone & Email (2 columns on web)
        _isWeb
            ? Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Phone Number',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: 'Enter phone number',
                            prefixIcon: const Icon(
                              Icons.phone,
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
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Email Address',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'Enter email address',
                            prefixIcon: const Icon(
                              Icons.email,
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
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Phone Number',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      hintText: 'Enter phone number',
                      prefixIcon: const Icon(Icons.phone, color: Colors.grey),
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
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Email Address',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'Enter email address',
                      prefixIcon: const Icon(Icons.email, color: Colors.grey),
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
              ),

        const SizedBox(height: 16),

        // Description
        const Text(
          'Description (Optional)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _descriptionController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Tell customers about your salon...',
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

  // ✅ Create Button
  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: (_isLoading || _isUploading) ? null : _createSalon,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isLoading || _isUploading
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
                  Text(_isUploading ? 'Uploading...' : 'Creating...'),
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

  // 📸 Show image source dialog
  void _showImageSourceDialog() {
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
                'Select Image Source',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: Color(0xFFFF6B8B),
              ),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFFF6B8B)),
              title: const Text('Take a Photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            if (_imageFile != null || _imageUrl != null)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove Image',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _imageFile = null;
                    _imageUrl = null;
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
