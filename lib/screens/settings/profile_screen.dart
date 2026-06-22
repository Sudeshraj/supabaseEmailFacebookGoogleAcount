// lib/screens/profile/profile_screen.dart

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/profile_service.dart';

// =====================================================
// PROFILE IMAGE PICKER WIDGET - Cross Platform
// =====================================================
class ProfileImagePicker extends StatelessWidget {
  final String? currentImageUrl;
  final dynamic tempImage; //  Temporary image for preview
  final String? fullName;
  final bool isLoading;
  final Function(dynamic) onImageSelected; // File or Uint8List
  final Function() onRemoveImage;

  const ProfileImagePicker({
    super.key,
    this.currentImageUrl,
    this.tempImage,
    this.fullName,
    this.isLoading = false,
    required this.onImageSelected,
    required this.onRemoveImage,
  });

  Future<void> _pickImage(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Change Profile Photo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.blue),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final image = await picker.pickImage(
                  source: ImageSource.gallery,
                  maxWidth: 800,
                  maxHeight: 800,
                  imageQuality: 80,
                );
                if (image != null) {
                  if (kIsWeb) {
                    final bytes = await image.readAsBytes();
                    onImageSelected(bytes);
                  } else {
                    onImageSelected(File(image.path));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.green),
              title: const Text('Take a Photo'),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final image = await picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 800,
                  maxHeight: 800,
                  imageQuality: 80,
                );
                if (image != null) {
                  if (kIsWeb) {
                    final bytes = await image.readAsBytes();
                    onImageSelected(bytes);
                  } else {
                    onImageSelected(File(image.path));
                  }
                }
              },
            ),
            if (currentImageUrl != null && currentImageUrl!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Remove Photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onRemoveImage();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ✅ Get image to display (priority: tempImage > currentImageUrl)
  ImageProvider? _getImageProvider() {
    // ✅ If there's a temporary image (selected but not uploaded)
    if (tempImage != null) {
      if (kIsWeb && tempImage is Uint8List) {
        return MemoryImage(tempImage as Uint8List);
      } else if (!kIsWeb && tempImage is File) {
        return FileImage(tempImage as File);
      }
    }

    // ✅ If there's a current image URL
    if (currentImageUrl != null && currentImageUrl!.isNotEmpty) {
      return NetworkImage(currentImageUrl!);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final imageProvider = _getImageProvider();

    return GestureDetector(
      onTap: isLoading ? null : () => _pickImage(context),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Colors.grey[200],
            backgroundImage: imageProvider,
            child: imageProvider == null
                ? Text(
                    fullName != null && fullName!.isNotEmpty
                        ? fullName![0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  )
                : null,
          ),
          if (isLoading)
            Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black26,
              ),
              child: const Center(
                child: SizedBox(
                  height: 30,
                  width: 30,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFFF6B8B),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// =====================================================
// ROLE BADGE WIDGET
// =====================================================
class RoleBadge extends StatelessWidget {
  final String role;
  final bool isSelected;

  const RoleBadge({super.key, required this.role, this.isSelected = false});

  @override
  Widget build(BuildContext context) {
    final service = ProfileService();
    final icon = service.getRoleIcon(role);
    final color = service.getRoleColor(role);
    final displayName = service.getRoleDisplayName(role);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected
            ? color.withValues(alpha: 0.15)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? color : Colors.grey.withValues(alpha: 0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            displayName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? color : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// MAIN PROFILE SCREEN
// =====================================================
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileService _profileService = ProfileService();
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;

  // Profile data
  String _userId = '';
  String _email = '';
  String _fullName = '';
  String _phone = '';
  String _bio = '';
  String _address = '';
  String _city = '';
  String _avatarUrl = '';
  List<String> _roles = [];
  String _joinedDate = '';

  // ✅ Temporary variables for editing
  String tempFullName = '';
  String tempPhone = '';
  String tempBio = '';
  String tempAddress = '';
  String tempCity = '';

  // ✅ Temporary image data for preview
  dynamic _tempSelectedImage; // File (mobile) or Uint8List (web)
  bool _hasImageChanged = false;
  bool _isImageRemoved = false;

  // Controllers for editing
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();

  // Image picker state
  final bool _isUploadingImage = false;

  // Which role is currently selected for display
  final int _selectedRoleIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please login again'),
              backgroundColor: Colors.red,
            ),
          );
          context.go('/login');
        }
        return;
      }

      _userId = currentUser.id;
      _email = currentUser.email ?? '';

      // Load profile
      final profile = await _profileService.getProfile(_userId);
      if (profile != null) {
        _fullName = profile['full_name'] ?? '';
        _phone = profile['phone'] ?? '';
        _bio = profile['bio'] ?? '';
        _address = profile['address'] ?? '';
        _city = profile['city'] ?? '';
        _avatarUrl = profile['avatar_url'] ?? '';
        _joinedDate = _formatDate(profile['created_at']);

        // Set controllers
        _fullNameController.text = _fullName;
        _phoneController.text = _phone;
        _bioController.text = _bio;
        _addressController.text = _address;
        _cityController.text = _city;

        // Set temp values
        tempFullName = _fullName;
        tempPhone = _phone;
        tempBio = _bio;
        tempAddress = _address;
        tempCity = _city;
      }

      // Load ALL user roles
      _roles = await _profileService.getUserRoles(_userId);

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return '';
    }
  }

  // =====================================================
  // ✅ IMAGE HANDLING - STORE TEMPORARILY WITH PREVIEW
  // =====================================================
  void _handleImageSelected(dynamic image) {
    setState(() {
      _tempSelectedImage = image;
      _hasImageChanged = true;
      _isImageRemoved = false;
    });

    // ✅ Show preview immediately
    _showSnackBar('📸 Image selected. Tap Save to update.', Colors.blue);
  }

  void _handleRemoveImage() {
    setState(() {
      _tempSelectedImage = null;
      _hasImageChanged = true;
      _isImageRemoved = true;
    });
    _showSnackBar('🗑️ Image will be removed on Save.', Colors.orange);
  }

  // =====================================================
  // ✅ PROFILE SAVE - UPLOAD IMAGE HERE
  // =====================================================
  Future<void> _saveProfile() async {
    // ✅ Validate changes
    final newFullName = _fullNameController.text.trim();
    final newPhone = _phoneController.text.trim();
    final newBio = _bioController.text.trim();
    final newAddress = _addressController.text.trim();
    final newCity = _cityController.text.trim();

    // Check if anything changed
    bool hasTextChanges = false;
    if (newFullName != _fullName) hasTextChanges = true;
    if (newPhone != _phone) hasTextChanges = true;
    if (newBio != _bio) hasTextChanges = true;
    if (newAddress != _address) hasTextChanges = true;
    if (newCity != _city) hasTextChanges = true;

    if (!hasTextChanges && !_hasImageChanged && !_isImageRemoved) {
      _showSnackBar('No changes to save', Colors.orange);
      return;
    }

    setState(() => _isSaving = true);

    try {
      String? newAvatarUrl = _avatarUrl;

      // ✅ Upload image ONLY if changed
      if (_isImageRemoved) {
        // Remove image
        if (_avatarUrl.isNotEmpty) {
          await _profileService.deleteOldImage(_avatarUrl);
        }
        newAvatarUrl = '';
      } else if (_hasImageChanged && _tempSelectedImage != null) {
        // ✅ Show loading dialog (only during save)
        _showSavingDialog();

        // Get file name for web
        String? fileName;
        if (kIsWeb && _tempSelectedImage is Uint8List) {
          fileName = '${_userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        }

        // Upload image
        final imageUrl = await _profileService.uploadProfileImage(
          userId: _userId,
          imageFile: _tempSelectedImage!,
          fileName: fileName,
        );

        // Close loading dialog
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }

        if (imageUrl != null) {
          // Delete old image if exists
          if (_avatarUrl.isNotEmpty) {
            await _profileService.deleteOldImage(_avatarUrl);
          }
          newAvatarUrl = imageUrl;
        } else {
          throw Exception('Failed to upload image');
        }
      }

      // ✅ Update profile with all changes
      final success = await _profileService.updateProfile(
        userId: _userId,
        fullName: newFullName,
        phone: newPhone.isEmpty ? null : newPhone,
        bio: newBio.isEmpty ? null : newBio,
        address: newAddress.isEmpty ? null : newAddress,
        city: newCity.isEmpty ? null : newCity,
        avatarUrl: newAvatarUrl,
      );

      if (success && mounted) {
        // ✅ Update state with new values
        setState(() {
          _fullName = newFullName;
          _phone = newPhone;
          _bio = newBio;
          _address = newAddress;
          _city = newCity;
          _avatarUrl = newAvatarUrl!;
          _isEditing = false;
          _isSaving = false;

          // ✅ Reset temp values
          _tempSelectedImage = null;
          _hasImageChanged = false;
          _isImageRemoved = false;
        });

        _showSnackBar('✅ Profile updated successfully', Colors.green);
      } else {
        setState(() => _isSaving = false);
        _showSnackBar('Failed to update profile', Colors.red);
      }
    } catch (e) {
      setState(() => _isSaving = false);

      // Close loading dialog if open
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      _showSnackBar('Error: $e', Colors.red);
    }
  }

  void _showSavingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: 50,
                width: 50,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B8B)),
                  strokeWidth: 4,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Saving Profile',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF6B8B),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please wait...',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: Colors.grey[200],
                  color: const Color(0xFFFF6B8B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _fullNameController.text = _fullName;
      _phoneController.text = _phone;
      _bioController.text = _bio;
      _addressController.text = _address;
      _cityController.text = _city;

      // ✅ Reset temp image changes
      _tempSelectedImage = null;
      _hasImageChanged = false;
      _isImageRemoved = false;
    });
  }

  // =====================================================
  // UI BUILDERS
  // =====================================================
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? 'Not provided' : value,
              style: TextStyle(
                fontSize: 14,
                color: value.isEmpty ? Colors.grey[400] : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: const Color(0xFFFF6B8B)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  // =====================================================
  // BUILD METHOD
  // =====================================================
  @override
  Widget build(BuildContext context) {
    // ✅ Get display image for preview
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Profile',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (!_isLoading && !_isEditing)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() => _isEditing = true),
            ),
          if (_isEditing)
            TextButton(
              onPressed: _isSaving ? null : _saveProfile,
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Save',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          if (_isEditing)
            TextButton(
              onPressed: _isSaving ? null : _cancelEditing,
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 16,
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // ✅ Profile Image Section with Preview
                  Center(
                    child: Column(
                      children: [
                        ProfileImagePicker(
                          currentImageUrl: _isImageRemoved ? null : _avatarUrl,
                          tempImage:
                              _tempSelectedImage, // ✅ Pass temp image for preview
                          fullName: _fullName,
                          isLoading: _isUploadingImage || _isSaving,
                          onImageSelected: _handleImageSelected,
                          onRemoveImage: _handleRemoveImage,
                        ),
                        const SizedBox(height: 12),

                        // ✅ Show preview status
                        if (_isEditing && _hasImageChanged)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _isImageRemoved
                                  ? Colors.red.withValues(alpha: 0.1)
                                  : Colors.blue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isImageRemoved
                                    ? Colors.red.withValues(alpha: 0.3)
                                    : Colors.blue.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _isImageRemoved
                                      ? Icons.warning_amber_rounded
                                      : Icons.photo_library,
                                  size: 16,
                                  color: _isImageRemoved
                                      ? Colors.red
                                      : Colors.blue,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _isImageRemoved
                                      ? 'Image will be removed'
                                      : 'New image selected (preview)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _isImageRemoved
                                        ? Colors.red
                                        : Colors.blue,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 8),
                        Text(
                          _fullName.isEmpty ? 'Add your name' : _fullName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _email,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (_joinedDate.isNotEmpty)
                          Text(
                            'Joined: $_joinedDate',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Role Badges - All roles from database
                  if (_roles.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        children: [
                          const Text(
                            'Your Roles',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: _roles.asMap().entries.map((entry) {
                              final index = entry.key;
                              final role = entry.value;
                              return RoleBadge(
                                role: role,
                                isSelected: index == _selectedRoleIndex,
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Profile Details
                  if (_isEditing) _buildEditForm() else _buildViewMode(),

                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  // =====================================================
  // VIEW MODE
  // =====================================================
  Widget _buildViewMode() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildInfoRow('Full Name', _fullName),
            const Divider(),
            _buildInfoRow('Phone', _phone),
            const Divider(),
            _buildInfoRow('Bio', _bio.isEmpty ? 'No bio added' : _bio),
            const Divider(),
            _buildInfoRow(
              'Address',
              _address.isEmpty ? 'No address added' : _address,
            ),
            const Divider(),
            _buildInfoRow('City', _city.isEmpty ? 'No city added' : _city),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // EDIT MODE
  // =====================================================
  Widget _buildEditForm() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Edit Profile',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF6B8B),
              ),
            ),
            const SizedBox(height: 16),
            _buildEditableField(
              label: 'Full Name',
              controller: _fullNameController,
              icon: Icons.person_outline,
            ),
            _buildEditableField(
              label: 'Phone Number',
              controller: _phoneController,
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            _buildEditableField(
              label: 'Bio',
              controller: _bioController,
              icon: Icons.description_outlined,
              maxLines: 3,
            ),
            _buildEditableField(
              label: 'Address',
              controller: _addressController,
              icon: Icons.home_outlined,
            ),
            _buildEditableField(
              label: 'City',
              controller: _cityController,
              icon: Icons.location_city_outlined,
            ),
          ],
        ),
      ),
    );
  }
}
