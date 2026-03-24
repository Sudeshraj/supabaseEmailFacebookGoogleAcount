import 'dart:io' show Platform, File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
  // Basic info controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // ============================================
  // GENDER SECTION
  // ============================================
  final List<Map<String, dynamic>> _addedGenders = [];
  final TextEditingController _genderDisplayNameController = TextEditingController();
  final TextEditingController _genderDisplayOrderController = TextEditingController();
  
  // Global data for suggestions
  List<Map<String, dynamic>> _globalGenders = [];
  bool _isLoadingGenders = false;

  // ============================================
  // AGE CATEGORY SECTION
  // ============================================
  final List<Map<String, dynamic>> _addedAgeCategories = [];
  final TextEditingController _ageCategoryDisplayNameController = TextEditingController();
  final TextEditingController _ageCategoryMinAgeController = TextEditingController();
  final TextEditingController _ageCategoryMaxAgeController = TextEditingController();
  final TextEditingController _ageCategoryDisplayOrderController = TextEditingController();
  
  // Global data for suggestions
  List<Map<String, dynamic>> _globalAgeCategories = [];
  bool _isLoadingAgeCategories = false;

  // ============================================
  // SERVICE CATEGORY SECTION
  // ============================================
  final List<Map<String, dynamic>> _addedServiceCategories = [];
  final TextEditingController _serviceCategoryDisplayNameController = TextEditingController();
  final TextEditingController _serviceCategoryDescriptionController = TextEditingController();
  final TextEditingController _serviceCategoryIconController = TextEditingController();
  final TextEditingController _serviceCategoryColorController = TextEditingController();
  final TextEditingController _serviceCategoryDisplayOrderController = TextEditingController();
  
  // Global data for suggestions
  List<Map<String, dynamic>> _globalCategories = [];
  bool _isLoadingCategories = false;

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
    
    // Set default values
    _genderDisplayOrderController.text = '0';
    _ageCategoryDisplayOrderController.text = '0';
    _serviceCategoryDisplayOrderController.text = '0';
    _ageCategoryMinAgeController.text = '0';
    _ageCategoryMaxAgeController.text = '100';
    
    // Load global data for suggestions
    _loadGlobalGenders();
    _loadGlobalAgeCategories();
    _loadGlobalCategories();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();
    
    _genderDisplayNameController.dispose();
    _genderDisplayOrderController.dispose();
    
    _ageCategoryDisplayNameController.dispose();
    _ageCategoryMinAgeController.dispose();
    _ageCategoryMaxAgeController.dispose();
    _ageCategoryDisplayOrderController.dispose();
    
    _serviceCategoryDisplayNameController.dispose();
    _serviceCategoryDescriptionController.dispose();
    _serviceCategoryIconController.dispose();
    _serviceCategoryColorController.dispose();
    _serviceCategoryDisplayOrderController.dispose();
    
    super.dispose();
  }

  // ============================================
  // LOAD GLOBAL DATA FOR SUGGESTIONS
  // ============================================
  
  Future<void> _loadGlobalGenders() async {
    setState(() => _isLoadingGenders = true);
    try {
      final response = await supabase
          .from('genders')
          .select('display_name, display_order')
          .eq('is_active', true)
          .order('display_order');
      
      setState(() {
        _globalGenders = List<Map<String, dynamic>>.from(response);
        _isLoadingGenders = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading genders: $e');
      setState(() => _isLoadingGenders = false);
    }
  }

  Future<void> _loadGlobalAgeCategories() async {
    setState(() => _isLoadingAgeCategories = true);
    try {
      final response = await supabase
          .from('age_categories')
          .select('display_name, min_age, max_age, display_order')
          .eq('is_active', true)
          .order('display_order');
      
      setState(() {
        _globalAgeCategories = List<Map<String, dynamic>>.from(response);
        _isLoadingAgeCategories = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading age categories: $e');
      setState(() => _isLoadingAgeCategories = false);
    }
  }

  Future<void> _loadGlobalCategories() async {
    setState(() => _isLoadingCategories = true);
    try {
      final response = await supabase
          .from('categories')
          .select('name, description, icon_name, color, display_order')
          .eq('is_active', true)
          .order('display_order');
      
      setState(() {
        _globalCategories = List<Map<String, dynamic>>.from(response);
        _isLoadingCategories = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading categories: $e');
      setState(() => _isLoadingCategories = false);
    }
  }

  // ============================================
  // AUTO-FILL FUNCTIONS
  // ============================================
  
  void _autoFillGender(Map<String, dynamic> selectedGender) {
    setState(() {
      _genderDisplayNameController.text = selectedGender['display_name'] ?? '';
      _genderDisplayOrderController.text = (selectedGender['display_order'] ?? 0).toString();
    });
  }

  void _autoFillAgeCategory(Map<String, dynamic> selectedAgeCat) {
    setState(() {
      _ageCategoryDisplayNameController.text = selectedAgeCat['display_name'] ?? '';
      _ageCategoryMinAgeController.text = (selectedAgeCat['min_age'] ?? 0).toString();
      _ageCategoryMaxAgeController.text = (selectedAgeCat['max_age'] ?? 100).toString();
      _ageCategoryDisplayOrderController.text = (selectedAgeCat['display_order'] ?? 0).toString();
    });
  }

  void _autoFillServiceCategory(Map<String, dynamic> selectedCategory) {
    setState(() {
      _serviceCategoryDisplayNameController.text = selectedCategory['name'] ?? '';
      _serviceCategoryDescriptionController.text = selectedCategory['description'] ?? '';
      _serviceCategoryIconController.text = selectedCategory['icon_name'] ?? '';
      _serviceCategoryColorController.text = selectedCategory['color'] ?? '#FF6B8B';
      _serviceCategoryDisplayOrderController.text = (selectedCategory['display_order'] ?? 0).toString();
    });
  }

  // ============================================
  // ADD FUNCTIONS
  // ============================================
  
  void _addGender() {
    final displayName = _genderDisplayNameController.text.trim();
    
    if (displayName.isEmpty) {
      _showSnackBar('Display name is required', Colors.orange);
      return;
    }

    if (_addedGenders.any((g) => g['display_name'] == displayName)) {
      _showSnackBar('This gender is already added', Colors.orange);
      return;
    }

    setState(() {
      _addedGenders.add({
        'display_name': displayName,
        'display_order': int.tryParse(_genderDisplayOrderController.text.trim()) ?? 0,
        'is_active': true,
      });
      
      _genderDisplayNameController.clear();
      _genderDisplayOrderController.text = '0';
    });
    
    _showSnackBar('Gender added successfully', Colors.green);
  }

  void _addAgeCategory() {
    final displayName = _ageCategoryDisplayNameController.text.trim();
    final minAge = int.tryParse(_ageCategoryMinAgeController.text.trim());
    final maxAge = int.tryParse(_ageCategoryMaxAgeController.text.trim());
    
    if (displayName.isEmpty) {
      _showSnackBar('Display name is required', Colors.orange);
      return;
    }
    if (minAge == null) {
      _showSnackBar('Minimum age is required', Colors.orange);
      return;
    }
    if (maxAge == null) {
      _showSnackBar('Maximum age is required', Colors.orange);
      return;
    }
    if (minAge > maxAge) {
      _showSnackBar('Minimum age cannot be greater than maximum age', Colors.orange);
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
        'display_order': int.tryParse(_ageCategoryDisplayOrderController.text.trim()) ?? 0,
        'is_active': true,
      });
      
      _ageCategoryDisplayNameController.clear();
      _ageCategoryMinAgeController.text = '0';
      _ageCategoryMaxAgeController.text = '100';
      _ageCategoryDisplayOrderController.text = '0';
    });
    
    _showSnackBar('Age category added successfully', Colors.green);
  }

  void _addServiceCategory() {
    final displayName = _serviceCategoryDisplayNameController.text.trim();
    
    if (displayName.isEmpty) {
      _showSnackBar('Display name is required', Colors.orange);
      return;
    }

    if (_addedServiceCategories.any((c) => c['display_name'] == displayName)) {
      _showSnackBar('This service category is already added', Colors.orange);
      return;
    }

    setState(() {
      _addedServiceCategories.add({
        'display_name': displayName,
        'description': _serviceCategoryDescriptionController.text.trim(),
        'icon_name': _serviceCategoryIconController.text.trim().isEmpty 
            ? 'build' 
            : _serviceCategoryIconController.text.trim(),
        'custom_color': _serviceCategoryColorController.text.trim().isEmpty 
            ? '#FF6B8B' 
            : _serviceCategoryColorController.text.trim(),
        'display_order': int.tryParse(_serviceCategoryDisplayOrderController.text.trim()) ?? 0,
        'is_active': true,
      });
      
      _serviceCategoryDisplayNameController.clear();
      _serviceCategoryDescriptionController.clear();
      _serviceCategoryIconController.clear();
      _serviceCategoryColorController.clear();
      _serviceCategoryDisplayOrderController.text = '0';
    });
    
    _showSnackBar('Service category added successfully', Colors.green);
  }

  // Remove functions
  void _removeGender(int index) {
    setState(() {
      _addedGenders.removeAt(index);
    });
    _showSnackBar('Gender removed', Colors.red);
  }

  void _removeAgeCategory(int index) {
    setState(() {
      _addedAgeCategories.removeAt(index);
    });
    _showSnackBar('Age category removed', Colors.red);
  }

  void _removeServiceCategory(int index) {
    setState(() {
      _addedServiceCategories.removeAt(index);
    });
    _showSnackBar('Service category removed', Colors.red);
  }

  // ============================================
  // CREATE SALON
  // ============================================
  
  Future<void> _createSalon() async {
    if (!_formKey.currentState!.validate()) return;

    if (_addedGenders.isEmpty) {
      _showSnackBar('Please add at least one gender', Colors.orange);
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
      // Upload images
      String? logoUrl = (_logoFile != null || _logoWebBytes != null)
          ? await _uploadLogo()
          : null;
      String? coverUrl = (_coverFile != null || _coverWebBytes != null)
          ? await _uploadCover()
          : null;

      // Create salon
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

      // Save Genders to salon_genders
      for (var gender in _addedGenders) {
        await supabase.from('salon_genders').insert({
          'salon_id': salonId,
          'display_name': gender['display_name'],
          'display_order': gender['display_order'],
          'is_active': gender['is_active'],
        });
      }

      // Save Age Categories to salon_age_categories
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

      // Save Service Categories to salon_categories
      for (var serviceCat in _addedServiceCategories) {
        await supabase.from('salon_categories').insert({
          'salon_id': salonId,
          'display_name': serviceCat['display_name'],
          'description': serviceCat['description'],
          'icon_name': serviceCat['icon_name'],
          'custom_color': serviceCat['custom_color'],
          'display_order': serviceCat['display_order'],
          'is_active': serviceCat['is_active'],
        });
      }

      if (!mounted) return;

      await showCustomAlert(
        context: context,
        title: "🎉 Salon Created!",
        message:
            "${_nameController.text.trim()} has been created successfully.\n\n"
            "✅ ${_addedGenders.length} genders added\n"
            "✅ ${_addedAgeCategories.length} age categories added\n"
            "✅ ${_addedServiceCategories.length} service categories added\n\n"
            "You can manage these from the salon management screen.",
        isError: false,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
      
    } catch (e) {
      debugPrint('❌ Error creating salon: $e');
      if (mounted) {
        _showSnackBar('Error creating salon: $e', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ============================================
  // BUILD WIDGETS
  // ============================================
  
  Widget _buildGenderInputSection() {
    return _buildExpandableSection(
      title: 'Genders',
      icon: Icons.people,
      color: Colors.blue,
      isLoading: _isLoadingGenders,
      addedItems: _addedGenders,
      onRemove: _removeGender,
      itemDisplayName: (item) => item['display_name'],
      formFields: [
        _buildSuggestionTextField(
          controller: _genderDisplayNameController,
          label: 'Display Name *',
          hint: 'e.g., Male, Female, Unisex',
          icon: Icons.visibility,
          suggestions: _globalGenders.map((g) => g['display_name'] as String).toList(),
          onSuggestionSelected: (String value) {
            final selected = _globalGenders.firstWhere(
              (g) => g['display_name'] == value,
              orElse: () => {},
            );
            if (selected.isNotEmpty) {
              _autoFillGender(selected);
            }
          },
        ),
        _buildTextField(
          controller: _genderDisplayOrderController,
          label: 'Display Order',
          hint: '0, 1, 2...',
          icon: Icons.numbers,
          keyboardType: TextInputType.number,
        ),
      ],
      onAdd: _addGender,
    );
  }

  Widget _buildAgeCategoryInputSection() {
    return _buildExpandableSection(
      title: 'Age Categories',
      icon: Icons.calendar_today,
      color: Colors.green,
      isLoading: _isLoadingAgeCategories,
      addedItems: _addedAgeCategories,
      onRemove: _removeAgeCategory,
      itemDisplayName: (item) => '${item['display_name']} (${item['min_age']}-${item['max_age']})',
      formFields: [
        _buildSuggestionTextField(
          controller: _ageCategoryDisplayNameController,
          label: 'Display Name *',
          hint: 'e.g., Child, Teen, Adult, Senior',
          icon: Icons.visibility,
          suggestions: _globalAgeCategories.map((a) => a['display_name'] as String).toList(),
          onSuggestionSelected: (String value) {
            final selected = _globalAgeCategories.firstWhere(
              (a) => a['display_name'] == value,
              orElse: () => {},
            );
            if (selected.isNotEmpty) {
              _autoFillAgeCategory(selected);
            }
          },
        ),
        _buildTextField(
          controller: _ageCategoryMinAgeController,
          label: 'Minimum Age *',
          hint: '0',
          icon: Icons.numbers,
          keyboardType: TextInputType.number,
        ),
        _buildTextField(
          controller: _ageCategoryMaxAgeController,
          label: 'Maximum Age *',
          hint: '100',
          icon: Icons.numbers,
          keyboardType: TextInputType.number,
        ),
        _buildTextField(
          controller: _ageCategoryDisplayOrderController,
          label: 'Display Order',
          hint: '0, 1, 2...',
          icon: Icons.numbers,
          keyboardType: TextInputType.number,
        ),
      ],
      onAdd: _addAgeCategory,
    );
  }

  Widget _buildServiceCategoryInputSection() {
    return _buildExpandableSection(
      title: 'Service Categories',
      icon: Icons.category,
      color: Colors.orange,
      isLoading: _isLoadingCategories,
      addedItems: _addedServiceCategories,
      onRemove: _removeServiceCategory,
      itemDisplayName: (item) => item['display_name'],
      formFields: [
        _buildSuggestionTextField(
          controller: _serviceCategoryDisplayNameController,
          label: 'Display Name *',
          hint: 'e.g., Hair, Skin, Nails, Grooming',
          icon: Icons.category,
          suggestions: _globalCategories.map((c) => c['name'] as String).toList(),
          onSuggestionSelected: (String value) {
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
        _buildTextField(
          controller: _serviceCategoryIconController,
          label: 'Icon Name',
          hint: 'e.g., content_cut, face, handshake',
          icon: Icons.emoji_symbols,
        ),
        _buildTextField(
          controller: _serviceCategoryColorController,
          label: 'Custom Color',
          hint: 'e.g., #FF6B8B, #4CAF50',
          icon: Icons.color_lens,
        ),
        _buildTextField(
          controller: _serviceCategoryDisplayOrderController,
          label: 'Display Order',
          hint: '0, 1, 2...',
          icon: Icons.numbers,
          keyboardType: TextInputType.number,
        ),
      ],
      onAdd: _addServiceCategory,
    );
  }

  Widget _buildExpandableSection({
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
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, color: color),
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
                // Form Fields
                ...formFields,
                const SizedBox(height: 12),
                
                // Add Button
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
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                
                // Added Items List
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
                        leading: const Icon(Icons.check_circle, color: Colors.green),
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: Colors.grey),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required List<String> suggestions,
    required Function(String) onSuggestionSelected,
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
          return suggestions.where((String option) {
            return option
                .toLowerCase()
                .contains(textEditingValue.text.toLowerCase());
          });
        },
        onSelected: (String selection) {
          onSuggestionSelected(selection);
        },
        fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
          // Sync with external controller
          if (textEditingController.text != controller.text) {
            textEditingController.text = controller.text;
          }
          
          controller.addListener(() {
            if (textEditingController.text != controller.text) {
              textEditingController.text = controller.text;
            }
          });
          
          return TextFormField(
            controller: textEditingController,
            focusNode: focusNode,
            keyboardType: keyboardType,
            maxLines: maxLines,
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              prefixIcon: Icon(icon, color: Colors.grey),
              suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
              ),
            ),
            onChanged: (value) {
              controller.text = value;
            },
          );
        },
      ),
    );
  }

  // ============================================
  // HELPER METHODS
  // ============================================
  
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
        await supabase.storage.from('salon-images').uploadBinary(filePath, _logoWebBytes!);
        return supabase.storage.from('salon-images').getPublicUrl(filePath);
      } else if (_logoFile != null) {
        final fileExt = path.extension(_logoFile!.path);
        fileName = 'logo_${DateTime.now().millisecondsSinceEpoch}$fileExt';
        final filePath = 'salons/$userId/$fileName';
        await supabase.storage.from('salon-images').upload(filePath, _logoFile!);
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
        await supabase.storage.from('salon-images').uploadBinary(filePath, _coverWebBytes!);
        return supabase.storage.from('salon-images').getPublicUrl(filePath);
      } else if (_coverFile != null) {
        final fileExt = path.extension(_coverFile!.path);
        fileName = 'cover_${DateTime.now().millisecondsSinceEpoch}$fileExt';
        final filePath = 'salons/$userId/$fileName';
        await supabase.storage.from('salon-images').upload(filePath, _coverFile!);
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

  String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
  }

  String _getPlatformName() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'mobile';
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _selectTime(BuildContext context, bool isOpenTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isOpenTime ? _openTime! : _closeTime!,
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

  // ============================================
  // MAIN BUILD
  // ============================================
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Salon'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        color: Colors.grey[50],
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _isWeb ? 1200 : double.infinity,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(_isWeb ? 32 : 16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildBasicInfoCard(),
                    const SizedBox(height: 16),
                    _buildBusinessHoursCard(),
                    const SizedBox(height: 16),
                    _buildContactCard(),
                    const SizedBox(height: 16),
                    _buildGenderInputSection(),
                    _buildAgeCategoryInputSection(),
                    _buildServiceCategoryInputSection(),
                    const SizedBox(height: 24),
                    _buildCreateButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBasicInfoCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Basic Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 1, child: _buildLogoSection()),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _buildCoverImageSection()),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _nameController,
              label: 'Salon Name',
              hint: 'Enter salon name',
              icon: Icons.store,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _addressController,
              label: 'Address',
              hint: 'Enter salon address',
              icon: Icons.location_on,
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _descriptionController,
              label: 'Description',
              hint: 'Tell customers about your salon',
              icon: Icons.description,
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    bool hasLogo = (kIsWeb && _logoWebBytes != null) || _logoFile != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Logo', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _isUploadingLogo ? null : () => _showLogoImageSourceDialog(),
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(60),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: hasLogo
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(60),
                    child: kIsWeb && _logoWebBytes != null
                        ? Image.memory(_logoWebBytes!, fit: BoxFit.cover)
                        : Image.file(_logoFile!, fit: BoxFit.cover),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo, size: 30, color: Colors.grey),
                      SizedBox(height: 4),
                      Text('Add Logo', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
          ),
        ),
        if (_isUploadingLogo)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildCoverImageSection() {
    bool hasCover = (kIsWeb && _coverWebBytes != null) || _coverFile != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Cover Image', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _isUploadingCover ? null : () => _showCoverImageSourceDialog(),
          child: Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: hasCover
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: kIsWeb && _coverWebBytes != null
                        ? Image.memory(_coverWebBytes!, fit: BoxFit.cover)
                        : Image.file(_coverFile!, fit: BoxFit.cover),
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate, size: 30, color: Colors.grey),
                        SizedBox(height: 4),
                        Text('Add Cover', style: TextStyle(color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                  ),
          ),
        ),
        if (_isUploadingCover)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildBusinessHoursCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Business Hours',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[400]!),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Text(
                  time.format(context),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Contact Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: _phoneController,
              label: 'Phone Number',
              hint: 'Enter phone number',
              icon: Icons.phone,
            ),
            const SizedBox(height: 12),
            _buildTextField(
              controller: _emailController,
              label: 'Email Address',
              hint: 'Enter email address',
              icon: Icons.email,
            ),
          ],
        ),
      ),
    );
  }

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
                    _isUploadingLogo || _isUploadingCover ? 'Uploading...' : 'Creating...',
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

  void _showLogoImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select Logo Source', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFFF6B8B)),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 800);
                if (picked != null) {
                  if (kIsWeb) {
                    final bytes = await picked.readAsBytes();
                    setState(() => _logoWebBytes = bytes);
                  } else {
                    setState(() => _logoFile = File(picked.path));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFFF6B8B)),
              title: const Text('Take a Photo'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickImage(source: ImageSource.camera, maxWidth: 800);
                if (picked != null) {
                  if (kIsWeb) {
                    final bytes = await picked.readAsBytes();
                    setState(() => _logoWebBytes = bytes);
                  } else {
                    setState(() => _logoFile = File(picked.path));
                  }
                }
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
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Select Cover Image Source', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFFF6B8B)),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1200);
                if (picked != null) {
                  if (kIsWeb) {
                    final bytes = await picked.readAsBytes();
                    setState(() => _coverWebBytes = bytes);
                  } else {
                    setState(() => _coverFile = File(picked.path));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFFF6B8B)),
              title: const Text('Take a Photo'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickImage(source: ImageSource.camera, maxWidth: 1200);
                if (picked != null) {
                  if (kIsWeb) {
                    final bytes = await picked.readAsBytes();
                    setState(() => _coverWebBytes = bytes);
                  } else {
                    setState(() => _coverFile = File(picked.path));
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}