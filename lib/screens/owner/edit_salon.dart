import 'dart:io' show File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:supabase_flutter/supabase_flutter.dart';

class EditSalonScreen extends StatefulWidget {
  final int salonId;

  const EditSalonScreen({super.key, required this.salonId});

  @override
  State<EditSalonScreen> createState() => _EditSalonScreenState();
}

class _EditSalonScreenState extends State<EditSalonScreen> {
  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Images
  File? _logoFile;
  Uint8List? _logoWebBytes;
  File? _coverFile;
  Uint8List? _coverWebBytes;
  String? _currentLogoUrl;
  String? _currentCoverUrl;
  bool _isUploadingLogo = false;
  bool _isUploadingCover = false;

  // Business hours
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;

  // Global selections (genders, age categories, categories)
  List<Map<String, dynamic>> _genders = [];
  List<Map<String, dynamic>> _ageCategories = [];
  List<Map<String, dynamic>> _categories = [];

  List<int> _selectedGenderIds = [];
  List<int> _selectedAgeCategoryIds = [];
  List<int> _selectedCategoryIds = [];

  bool _isLoadingGlobalData = false;
  bool _isLoadingSalonData = true;
  bool _isSaving = false;
  bool _isDeleting = false;

  // Form key
  final _formKey = GlobalKey<FormState>();

  // Responsive layout helpers
  bool get _isWeb => MediaQuery.of(context).size.width > 800;

  final supabase = Supabase.instance.client;
  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadSalonData();
    _loadGlobalData();
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

  // ============================================================
  // 🔥 Load salon data
  // ============================================================
  Future<void> _loadSalonData() async {
    setState(() => _isLoadingSalonData = true);

    try {
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

      if (response['open_time'] != null) {
        final openTimeStr = response['open_time'] as String;
        final openParts = openTimeStr.split(':');
        _openTime = TimeOfDay(
          hour: int.parse(openParts[0]),
          minute: int.parse(openParts[1]),
        );
      } else {
        _openTime = const TimeOfDay(hour: 9, minute: 0);
      }

      if (response['close_time'] != null) {
        final closeTimeStr = response['close_time'] as String;
        final closeParts = closeTimeStr.split(':');
        _closeTime = TimeOfDay(
          hour: int.parse(closeParts[0]),
          minute: int.parse(closeParts[1]),
        );
      } else {
        _closeTime = const TimeOfDay(hour: 18, minute: 0);
      }

      setState(() => _isLoadingSalonData = false);
    } catch (e) {
      debugPrint('❌ Error loading salon: $e');
      if (mounted) {
        _showSnackBar('Error loading salon data', Colors.red);
        Navigator.pop(context);
      }
    }
  }

  // ============================================================
  // 🔥 Load salon's selected items (only selected ones)
  // ============================================================
  Future<void> _loadSalonSelections() async {
    try {
      // Load selected genders
      final genderResponse = await supabase
          .from('salon_genders')
          .select('gender_id')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true);

      setState(() {
        _selectedGenderIds = genderResponse
            .map((e) => e['gender_id'] as int)
            .toList();
      });

      // Load selected age categories
      final ageResponse = await supabase
          .from('salon_age_categories')
          .select('age_category_id')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true);

      setState(() {
        _selectedAgeCategoryIds = ageResponse
            .map((e) => e['age_category_id'] as int)
            .toList();
      });

      // Load selected categories
      final categoryResponse = await supabase
          .from('salon_categories')
          .select('category_id')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true);

      setState(() {
        _selectedCategoryIds = categoryResponse
            .map((e) => e['category_id'] as int)
            .toList();
      });

      debugPrint('📊 Loaded selected items:');
      debugPrint('   Genders: $_selectedGenderIds');
      debugPrint('   Age Categories: $_selectedAgeCategoryIds');
      debugPrint('   Categories: $_selectedCategoryIds');
    } catch (e) {
      debugPrint('❌ Error loading salon selections: $e');
    }
  }

  // ============================================================
  // 🔥 Load global data (all available options)
  // ============================================================
  Future<void> _loadGlobalData() async {
    setState(() => _isLoadingGlobalData = true);

    try {
      final gendersResponse = await supabase
          .from('genders')
          .select()
          .eq('is_active', true)
          .order('display_order');

      final ageResponse = await supabase
          .from('age_categories')
          .select()
          .eq('is_active', true)
          .order('display_order');

      final categoriesResponse = await supabase
          .from('categories')
          .select()
          .eq('is_active', true)
          .order('display_order');

      setState(() {
        _genders = List<Map<String, dynamic>>.from(gendersResponse);
        _ageCategories = List<Map<String, dynamic>>.from(ageResponse);
        _categories = List<Map<String, dynamic>>.from(categoriesResponse);
        _isLoadingGlobalData = false;
      });

      await _loadSalonSelections();
    } catch (e) {
      debugPrint('❌ Error loading global data: $e');
      setState(() => _isLoadingGlobalData = false);
    }
  }


  // 📸 Pick logo image
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
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _logoWebBytes = bytes;
            _logoFile = null;
          });
        } else {
          setState(() {
            _logoFile = File(pickedFile.path);
            _logoWebBytes = null;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error picking logo: $e');
      if (mounted) _showSnackBar('Error picking logo', Colors.red);
    }
  }

  // 📸 Pick cover image
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
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _coverWebBytes = bytes;
            _coverFile = null;
          });
        } else {
          setState(() {
            _coverFile = File(pickedFile.path);
            _coverWebBytes = null;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error picking cover: $e');
      if (mounted) _showSnackBar('Error picking cover', Colors.red);
    }
  }

  // ☁️ Upload logo
  Future<String?> _uploadLogo() async {
    if (_logoFile == null && _logoWebBytes == null) return null;

    setState(() => _isUploadingLogo = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not logged in');

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
      debugPrint('❌ Error uploading logo: $e');
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  // ☁️ Upload cover
  Future<String?> _uploadCover() async {
    if (_coverFile == null && _coverWebBytes == null) return null;

    setState(() => _isUploadingCover = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not logged in');

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
      debugPrint('❌ Error uploading cover: $e');
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingCover = false);
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
            colorScheme: const ColorScheme.light(primary: Color(0xFFFF6B8B)),
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

  String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
  }

  // 💾 Update salon
  Future<void> _updateSalon() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      String? logoUrl = _currentLogoUrl;
      if (_logoFile != null || _logoWebBytes != null) {
        final newLogoUrl = await _uploadLogo();
        if (newLogoUrl != null) logoUrl = newLogoUrl;
      }

      String? coverUrl = _currentCoverUrl;
      if (_coverFile != null || _coverWebBytes != null) {
        final newCoverUrl = await _uploadCover();
        if (newCoverUrl != null) coverUrl = newCoverUrl;
      }

      // Update salon basic info
      final updateData = {
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
        'description': _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        'logo_url': logoUrl,
        'cover_url': coverUrl,
        'open_time': _formatTimeOfDay(_openTime!),
        'close_time': _formatTimeOfDay(_closeTime!),
        'updated_at': DateTime.now().toIso8601String(),
      };

      await supabase.from('salons').update(updateData).eq('id', widget.salonId);

      // Update genders (delete old, insert new)
      await supabase
          .from('salon_genders')
          .delete()
          .eq('salon_id', widget.salonId);

      if (_selectedGenderIds.isNotEmpty) {
        final genderInserts = _selectedGenderIds.map((genderId) {
          return {
            'salon_id': widget.salonId,
            'gender_id': genderId,
            'is_active': true,
          };
        }).toList();
        await supabase.from('salon_genders').insert(genderInserts);
      }

      // Update age categories
      await supabase
          .from('salon_age_categories')
          .delete()
          .eq('salon_id', widget.salonId);

      if (_selectedAgeCategoryIds.isNotEmpty) {
        final ageInserts = _selectedAgeCategoryIds.map((ageId) {
          return {
            'salon_id': widget.salonId,
            'age_category_id': ageId,
            'is_active': true,
          };
        }).toList();
        await supabase.from('salon_age_categories').insert(ageInserts);
      }

      // Update categories
      await supabase
          .from('salon_categories')
          .delete()
          .eq('salon_id', widget.salonId);

      if (_selectedCategoryIds.isNotEmpty) {
        final categoryInserts = _selectedCategoryIds.map((catId) {
          return {
            'salon_id': widget.salonId,
            'category_id': catId,
            'is_active': true,
          };
        }).toList();
        await supabase.from('salon_categories').insert(categoryInserts);
      }

      // 🔥 FIX: Store values before async gap
      final salonName = _nameController.text.trim();

      // 🔥 FIX: Check mounted before using context
      if (!mounted) return;

      await showCustomAlert(
        context: context,
        title: "✅ Salon Updated!",
        message: "$salonName has been updated successfully.",
        isError: false,
      );

      // 🔥 FIX: Check mounted again after async showCustomAlert
      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('❌ Error updating salon: $e');
      // 🔥 FIX: Check mounted before showing snackbar
      if (mounted) {
        _showSnackBar('Error updating salon', Colors.red);
      }
    } finally {
      // 🔥 FIX: Check mounted before setState
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  // 🗑️ Delete salon
  // 🗑️ Delete salon
  Future<void> _deleteSalon() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Text(
              'Delete Salon',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Are you sure you want to delete '${_nameController.text.trim()}'?",
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚠️ This will also delete:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text('• All appointments', style: TextStyle(fontSize: 13)),
                  Text('• All services', style: TextStyle(fontSize: 13)),
                  Text('• All barbers', style: TextStyle(fontSize: 13)),
                  Text('• All reviews', style: TextStyle(fontSize: 13)),
                  Text(
                    '• All service variants',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'This action cannot be undone!',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.red,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(fontSize: 16)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
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

    if (confirmed == true) {
      setState(() => _isDeleting = true);

      try {
        await supabase.from('salons').delete().eq('id', widget.salonId);

        // 🔥 FIX: Check mounted before showing snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Salon deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );

          // 🔥 FIX: Check mounted before pop
          if (mounted) {
            Navigator.pop(context, true);
          }
        }
      } catch (e) {
        debugPrint('❌ Error deleting salon: $e');
        if (mounted) {
          _showSnackBar('Error deleting salon', Colors.red);
        }
      } finally {
        if (mounted) {
          setState(() => _isDeleting = false);
        }
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ============================================================
  // 🔥 Build Multi-Select Chip
  // ============================================================
  Widget _buildMultiSelectChip({
    required String title,
    required List<Map<String, dynamic>> items,
    required List<int> selectedIds,
    required Function(int id, bool selected) onChanged,
  }) {
    if (items.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            final id = item['id'] as int;
            final isSelected = selectedIds.contains(id);
            final displayName =
                item['display_name'] as String? ??
                item['name'] as String? ??
                '';

            return FilterChip(
              label: Text(displayName),
              selected: isSelected,
              onSelected: (selected) => onChanged(id, selected),
              backgroundColor: Colors.white,
              selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
              checkmarkColor: const Color(0xFFFF6B8B),
              labelStyle: TextStyle(
                color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[700],
                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
              ),
              shape: StadiumBorder(
                side: BorderSide(
                  color: isSelected
                      ? const Color(0xFFFF6B8B)
                      : Colors.grey[300]!,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ============================================================
  // 🔥 Build Global Selections Section
  // ============================================================
  Widget _buildGlobalSelections() {
    if (_isLoadingGlobalData) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            children: [
              SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(height: 8),
              Text('Loading options...', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      );
    }

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
            'Select Services & Settings',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            'Choose what to offer at your salon (tap to select/unselect)',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Genders Selection
          _buildMultiSelectChip(
            title: 'Genders',
            items: _genders,
            selectedIds: _selectedGenderIds,
            onChanged: (id, selected) {
              setState(() {
                if (selected) {
                  if (!_selectedGenderIds.contains(id)) {
                    _selectedGenderIds.add(id);
                  }
                } else {
                  _selectedGenderIds.remove(id);
                }
              });
              debugPrint('Gender ${selected ? "selected" : "unselected"}: $id');
            },
          ),

          const SizedBox(height: 16),

          // Age Categories Selection
          _buildMultiSelectChip(
            title: 'Age Categories',
            items: _ageCategories,
            selectedIds: _selectedAgeCategoryIds,
            onChanged: (id, selected) {
              setState(() {
                if (selected) {
                  if (!_selectedAgeCategoryIds.contains(id)) {
                    _selectedAgeCategoryIds.add(id);
                  }
                } else {
                  _selectedAgeCategoryIds.remove(id);
                }
              });
            },
          ),

          const SizedBox(height: 16),

          // Categories Selection
          _buildMultiSelectChip(
            title: 'Service Categories',
            items: _categories,
            selectedIds: _selectedCategoryIds,
            onChanged: (id, selected) {
              setState(() {
                if (selected) {
                  if (!_selectedCategoryIds.contains(id)) {
                    _selectedCategoryIds.add(id);
                  }
                } else {
                  _selectedCategoryIds.remove(id);
                }
              });
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // 🔥 Build UI Components
  // ============================================================

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
            child: const Icon(Icons.edit, color: Color(0xFFFF6B8B), size: 48),
          ),
          const SizedBox(height: 16),
          const Text(
            'Edit Salon Details',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Update your salon information',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverImageSection() {
    bool hasCover =
        (kIsWeb && _coverWebBytes != null) ||
        _coverFile != null ||
        _currentCoverUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cover Image',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Upload a cover photo for your salon',
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
                            ? Image.memory(_coverWebBytes!, fit: BoxFit.cover)
                            : _coverFile != null
                            ? Image.file(_coverFile!, fit: BoxFit.cover)
                            : _currentCoverUrl != null
                            ? Image.network(
                                _currentCoverUrl!,
                                fit: BoxFit.cover,
                              )
                            : const SizedBox(),
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
                            onPressed: _showCoverImageSourceDialog,
                          ),
                        ),
                      ),
                    ],
                  )
                : _buildCoverPlaceholder(),
          ),
        ),
      ],
    );
  }

  Widget _buildCoverPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey[400]),
        const SizedBox(height: 8),
        Text('Add Cover Photo', style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildLogoSection() {
    bool hasLogo =
        (kIsWeb && _logoWebBytes != null) ||
        _logoFile != null ||
        _currentLogoUrl != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Logo',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Upload your salon logo',
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
                              ? Image.memory(_logoWebBytes!, fit: BoxFit.cover)
                              : _logoFile != null
                              ? Image.file(_logoFile!, fit: BoxFit.cover)
                              : _currentLogoUrl != null
                              ? Image.network(
                                  _currentLogoUrl!,
                                  fit: BoxFit.cover,
                                )
                              : const SizedBox(),
                        )
                      : _buildLogoPlaceholder(),
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

  Widget _buildLogoPlaceholder() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo, size: 30, color: Colors.grey),
        SizedBox(height: 4),
        Text('Add Logo', style: TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }

  Widget _buildBasicInfoFields() {
    return Column(
      children: [
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
          ),
          validator: (value) =>
              value?.trim().isEmpty ?? true ? 'Required' : null,
        ),
        const SizedBox(height: 16),
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

  Widget _buildContactSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contact Information',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
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
          ),
        ),
        const SizedBox(height: 12),
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
          'Tell customers about your salon',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _descriptionController,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Enter salon description...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey[700],
              side: BorderSide(color: Colors.grey[300]!),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: (_isSaving || _isUploadingLogo || _isUploadingCover)
                ? null
                : _updateSalon,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isSaving || _isUploadingLogo || _isUploadingCover
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text('Saving...'),
                    ],
                  )
                : const Text(
                    'Save Changes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

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
              leading: const Icon(
                Icons.photo_library,
                color: Color(0xFFFF6B8B),
              ),
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
            if (_logoFile != null ||
                _logoWebBytes != null ||
                _currentLogoUrl != null)
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
                    _currentLogoUrl = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

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
              leading: const Icon(
                Icons.photo_library,
                color: Color(0xFFFF6B8B),
              ),
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
            if (_coverFile != null ||
                _coverWebBytes != null ||
                _currentCoverUrl != null)
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
                    _currentCoverUrl = null;
                  });
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Salon'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: _isWeb,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _isDeleting ? null : _deleteSalon,
            tooltip: 'Delete Salon',
          ),
        ],
      ),
      body: _isLoadingSalonData
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : Container(
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
                              _buildHeader(),
                              const SizedBox(height: 32),
                              _buildCoverImageSection(),
                              const SizedBox(height: 24),
                              _isWeb
                                  ? Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 1,
                                          child: _buildLogoSection(),
                                        ),
                                        const SizedBox(width: 24),
                                        Expanded(
                                          flex: 2,
                                          child: _buildBasicInfoFields(),
                                        ),
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
                              _buildBusinessHoursSection(),
                              const SizedBox(height: 24),
                              _buildGlobalSelections(),
                              const SizedBox(height: 24),
                              _buildContactSection(),
                              const SizedBox(height: 24),
                              _buildDescriptionField(),
                              const SizedBox(height: 32),
                              _buildActionButtons(),
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
}
