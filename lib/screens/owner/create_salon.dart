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
  // GENDER SECTION - Using display_name instead of name
  // ============================================
  final List<Map<String, dynamic>> _addedGenders = [];
  final TextEditingController _genderDisplayNameController = TextEditingController();
  
  List<Map<String, dynamic>> _globalGenders = [];
  bool _isLoadingGenders = false;

  // ============================================
  // AGE CATEGORY SECTION - Using display_name instead of name
  // ============================================
  final List<Map<String, dynamic>> _addedAgeCategories = [];
  final TextEditingController _ageCategoryDisplayNameController = TextEditingController();
  final TextEditingController _ageCategoryMinAgeController = TextEditingController();
  final TextEditingController _ageCategoryMaxAgeController = TextEditingController();
  
  List<Map<String, dynamic>> _globalAgeCategories = [];
  bool _isLoadingAgeCategories = false;

  // ============================================
  // SERVICE CATEGORY SECTION - Using name (stays as name)
  // ============================================
  final List<Map<String, dynamic>> _addedServiceCategories = [];
  final TextEditingController _serviceCategoryNameController = TextEditingController();
  final TextEditingController _serviceCategoryDescriptionController = TextEditingController();
  
  String _selectedIcon = 'content_cut';
  Color _selectedColor = const Color(0xFFFF6B8B);
  
  List<Map<String, dynamic>> _globalCategories = [];
  bool _isLoadingCategories = false;

  // Icon list for selection
  final List<Map<String, dynamic>> _iconList = [
    {'name': 'content_cut', 'icon': Icons.content_cut, 'label': 'Scissors'},
    {'name': 'face', 'icon': Icons.face, 'label': 'Face'},
    {'name': 'face_retouching_natural', 'icon': Icons.face_retouching_natural, 'label': 'Beard'},
    {'name': 'spa', 'icon': Icons.spa, 'label': 'Spa'},
    {'name': 'handshake', 'icon': Icons.handshake, 'label': 'Nails'},
    {'name': 'build', 'icon': Icons.build, 'label': 'Tools'},
    {'name': 'cut', 'icon': Icons.cut, 'label': 'Hair Cut'},
    {'name': 'shower', 'icon': Icons.shower, 'label': 'Shower'},
    {'name': 'masks', 'icon': Icons.masks, 'label': 'Masks'},
    // {'name': 'beauty', 'icon': Icons.beauty, 'label': 'Beauty'},
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
    
    // Set default values
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
    
    _genderDisplayNameController.dispose();
    
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
      // Load genders - get display_name
      final genders = await supabase
          .from('genders')
          .select('display_name, display_order')
          .eq('is_active', true)
          .order('display_order');
          
      // Load age categories - get display_name, min_age, max_age
      final ageCategories = await supabase
          .from('age_categories')
          .select('display_name, min_age, max_age, display_order')
          .eq('is_active', true)
          .order('display_order');
          
      // Load categories - get name, description, icon_name, color
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

  // Auto-fill functions
  void _autoFillGender(Map<String, dynamic> selected) {
    setState(() {
      _genderDisplayNameController.text = selected['display_name']?.toString() ?? '';
    });
  }

  void _autoFillAgeCategory(Map<String, dynamic> selected) {
    setState(() {
      _ageCategoryDisplayNameController.text = selected['display_name']?.toString() ?? '';
      _ageCategoryMinAgeController.text = (selected['min_age'] ?? 0).toString();
      _ageCategoryMaxAgeController.text = (selected['max_age'] ?? 100).toString();
    });
  }

  void _autoFillServiceCategory(Map<String, dynamic> selected) {
    setState(() {
      _serviceCategoryNameController.text = selected['name']?.toString() ?? '';
      _serviceCategoryDescriptionController.text = selected['description']?.toString() ?? '';
      _selectedIcon = selected['icon_name']?.toString() ?? 'content_cut';
      
      // Handle color properly
      String colorStr = selected['color']?.toString() ?? '#FF6B8B';
      if (colorStr.startsWith('#')) {
        _selectedColor = Color(int.parse('0xFF${colorStr.substring(1)}'));
      } else {
        _selectedColor = const Color(0xFFFF6B8B);
      }
    });
  }

  // Add functions - UPDATED for correct schema
  void _addGender() {
    final displayName = _genderDisplayNameController.text.trim();
    if (displayName.isEmpty) {
      _showSnackBar('Gender display name is required', Colors.orange);
      return;
    }
    if (_addedGenders.any((g) => g['display_name'] == displayName)) {
      _showSnackBar('This gender is already added', Colors.orange);
      return;
    }

    setState(() {
      _addedGenders.add({
        'display_name': displayName,
        'display_order': _addedGenders.length,
        'is_active': true,
      });
      _genderDisplayNameController.clear();
    });
    _showSnackBar('Gender added', Colors.green);
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
        'color': '#${_selectedColor.value.toRadixString(16).substring(2)}',
        'display_order': _addedServiceCategories.length,
        'is_active': true,
      });
      _serviceCategoryNameController.clear();
      _serviceCategoryDescriptionController.clear();
    });
    _showSnackBar('Service category added', Colors.green);
  }

  void _removeGender(int index) {
    setState(() => _addedGenders.removeAt(index));
    for (int i = 0; i < _addedGenders.length; i++) {
      _addedGenders[i]['display_order'] = i;
    }
  }

  void _removeAgeCategory(int index) {
    setState(() => _addedAgeCategories.removeAt(index));
    for (int i = 0; i < _addedAgeCategories.length; i++) {
      _addedAgeCategories[i]['display_order'] = i;
    }
  }

  void _removeServiceCategory(int index) {
    setState(() => _addedServiceCategories.removeAt(index));
    for (int i = 0; i < _addedServiceCategories.length; i++) {
      _addedServiceCategories[i]['display_order'] = i;
    }
  }

  // Create Salon - UPDATED for correct schema
  Future<void> _createSalon() async {
    if (!_formKey.currentState!.validate()) return;

    if (_addedGenders.isEmpty) {
      _showSnackBar('Add at least one gender', Colors.orange);
      return;
    }
    if (_addedAgeCategories.isEmpty) {
      _showSnackBar('Add at least one age category', Colors.orange);
      return;
    }
    if (_addedServiceCategories.isEmpty) {
      _showSnackBar('Add at least one service category', Colors.orange);
      return;
    }

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      _showSnackBar('Please login first', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? logoUrl = (_logoFile != null || _logoWebBytes != null) ? await _uploadLogo() : null;
      String? coverUrl = (_coverFile != null || _coverWebBytes != null) ? await _uploadCover() : null;

      final salonData = {
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        'email': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        'owner_id': userId,
        'description': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        'logo_url': logoUrl,
        'cover_url': coverUrl,
        'open_time': _formatTimeOfDay(_openTime!),
        'close_time': _formatTimeOfDay(_closeTime!),
        'extra_data': {'created_from': _isWeb ? 'web' : 'mobile', 'platform': _getPlatformName()},
        'is_active': true,
      };

      final response = await supabase.from('salons').insert(salonData).select('id, name').single();
      final salonId = response['id'] as int;

      // Save genders to salon_genders - USING display_name (NOT name)
      for (var gender in _addedGenders) {
        await supabase.from('salon_genders').insert({
          'salon_id': salonId,
          'display_name': gender['display_name'],  // ✅ Correct: display_name
          'display_order': gender['display_order'],
          'is_active': gender['is_active'],
        });
      }

      // Save age categories to salon_age_categories - USING display_name (NOT name)
      for (var ageCat in _addedAgeCategories) {
        await supabase.from('salon_age_categories').insert({
          'salon_id': salonId,
          'display_name': ageCat['display_name'],  // ✅ Correct: display_name
          'min_age': ageCat['min_age'],
          'max_age': ageCat['max_age'],
          'display_order': ageCat['display_order'],
          'is_active': ageCat['is_active'],
        });
      }

      // Save service categories to salon_categories - USING name (stays as name)
      for (var serviceCat in _addedServiceCategories) {
        await supabase.from('salon_categories').insert({
          'salon_id': salonId,
          'name': serviceCat['name'],  // ✅ Correct: name
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
            "✅ ${_addedGenders.length} genders\n"
            "✅ ${_addedAgeCategories.length} age categories\n"
            "✅ ${_addedServiceCategories.length} service categories",
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
  // BUILD WIDGETS - UPDATED for correct schema
  // ============================================

  Widget _buildGenderSection() {
    return _buildSection(
      title: 'Genders',
      icon: Icons.people,
      color: Colors.blue,
      isLoading: _isLoadingGenders,
      addedItems: _addedGenders,
      onRemove: _removeGender,
      itemDisplayName: (item) => item['display_name'],
      formFields: [
        _buildSuggestionField(
          controller: _genderDisplayNameController,
          label: 'Display Name *',
          hint: 'e.g., Male, Female, Unisex',
          icon: Icons.visibility,
          suggestions: _globalGenders.map((g) => g['display_name'] as String).toList(),
          onSelected: (String value) {
            final selected = _globalGenders.firstWhere(
              (g) => g['display_name'] == value,
              orElse: () => {},
            );
            if (selected.isNotEmpty) {
              _autoFillGender(selected);
            }
          },
        ),
      ],
      onAdd: _addGender,
    );
  }

  Widget _buildAgeCategorySection() {
    return _buildSection(
      title: 'Age Categories',
      icon: Icons.calendar_today,
      color: Colors.green,
      isLoading: _isLoadingAgeCategories,
      addedItems: _addedAgeCategories,
      onRemove: _removeAgeCategory,
      itemDisplayName: (item) => '${item['display_name']} (${item['min_age']}-${item['max_age']})',
      formFields: [
        _buildSuggestionField(
          controller: _ageCategoryDisplayNameController,
          label: 'Display Name *',
          hint: 'e.g., Child, Teen, Adult, Senior',
          icon: Icons.visibility,
          suggestions: _globalAgeCategories.map((a) => a['display_name'] as String).toList(),
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

  Widget _buildServiceCategorySection() {
    return _buildSection(
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
          suggestions: _globalCategories.map((c) => c['name'] as String).toList(),
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

  Widget _buildIconSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Icon', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
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
                  width: 80,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFFF6B8B).withValues(alpha: 0.1) : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[300]!,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        iconItem['icon'] as IconData,
                        size: 32,
                        color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[600],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        iconItem['label'] as String,
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected ? const Color(0xFFFF6B8B) : Colors.grey[600],
                          fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                        ),
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
        const Text('Color', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
                  border: isSelected ? Border.all(color: Colors.white, width: 3) : null,
                  boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 2)] : null,
                ),
                child: isSelected ? const Center(child: Icon(Icons.check, color: Colors.white, size: 20)) : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSection({
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
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                if (addedItems.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('Added Items:', style: TextStyle(fontWeight: FontWeight.bold)),
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
          if (textEditingValue.text.isEmpty) return const Iterable<String>.empty();
          return suggestions.where((option) =>
              option.toLowerCase().contains(textEditingValue.text.toLowerCase()));
        },
        onSelected: (String selection) {
          onSelected(selection);
          controller.text = selection;
        },
        fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
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
              suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
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
      return null;
    } finally {
      if (mounted) setState(() => _isUploadingCover = false);
    }
  }

  String _formatTimeOfDay(TimeOfDay time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
  String _getPlatformName() => kIsWeb ? 'web' : Platform.isIOS ? 'ios' : Platform.isAndroid ? 'android' : 'mobile';
  
  void _showSnackBar(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _selectTime(BuildContext context, bool isOpen) async {
    final picked = await showTimePicker(context: context, initialTime: isOpen ? _openTime! : _closeTime!);
    if (picked != null) setState(() => isOpen ? _openTime = picked : _closeTime = picked);
  }

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
            constraints: BoxConstraints(maxWidth: _isWeb ? 1200 : double.infinity),
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
                    _buildGenderSection(),
                    _buildAgeCategorySection(),
                    _buildServiceCategorySection(),
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
          children: [
            const Text('Basic Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildLogoSection()),
                const SizedBox(width: 16),
                Expanded(child: _buildCoverImageSection()),
              ],
            ),
            const SizedBox(height: 16),
            _buildTextField(controller: _nameController, label: 'Salon Name', hint: 'Enter salon name', icon: Icons.store),
            const SizedBox(height: 12),
            _buildTextField(controller: _addressController, label: 'Address', hint: 'Enter address', icon: Icons.location_on, maxLines: 2),
            const SizedBox(height: 12),
            _buildTextField(controller: _descriptionController, label: 'Description', hint: 'Tell about your salon', icon: Icons.description, maxLines: 3),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoSection() {
    bool hasLogo = (kIsWeb && _logoWebBytes != null) || _logoFile != null;
    return Column(
      children: [
        const Text('Logo', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _showImageSourceDialog(isLogo: true),
          child: Container(
            width: 120, height: 120,
            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(60), border: Border.all(color: Colors.grey[300]!)),
            child: hasLogo ? ClipRRect(
              borderRadius: BorderRadius.circular(60),
              child: kIsWeb && _logoWebBytes != null ? Image.memory(_logoWebBytes!, fit: BoxFit.cover) : Image.file(_logoFile!, fit: BoxFit.cover),
            ) : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_a_photo, size: 30, color: Colors.grey),
              SizedBox(height: 4),
              Text('Add Logo', style: TextStyle(color: Colors.grey, fontSize: 11)),
            ]),
          ),
        ),
        if (_isUploadingLogo) const Padding(padding: EdgeInsets.only(top: 8), child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildCoverImageSection() {
    bool hasCover = (kIsWeb && _coverWebBytes != null) || _coverFile != null;
    return Column(
      children: [
        const Text('Cover Image', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _showImageSourceDialog(isLogo: false),
          child: Container(
            height: 120, width: double.infinity,
            decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[300]!)),
            child: hasCover ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: kIsWeb && _coverWebBytes != null ? Image.memory(_coverWebBytes!, fit: BoxFit.cover) : Image.file(_coverFile!, fit: BoxFit.cover),
            ) : const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.add_photo_alternate, size: 30, color: Colors.grey),
              SizedBox(height: 4),
              Text('Add Cover', style: TextStyle(color: Colors.grey, fontSize: 11)),
            ])),
          ),
        ),
        if (_isUploadingCover) const Padding(padding: EdgeInsets.only(top: 8), child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildBusinessHoursCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Business Hours', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildTimeTile('Open Time', _openTime!, Icons.access_time, () => _selectTime(context, true))),
                const SizedBox(width: 16),
                Expanded(child: _buildTimeTile('Close Time', _closeTime!, Icons.access_time, () => _selectTime(context, false))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeTile(String label, TimeOfDay time, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey[400]!), borderRadius: BorderRadius.circular(8), color: Colors.white),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              Text(time.format(context), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Contact Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildTextField(controller: _phoneController, label: 'Phone', hint: 'Enter phone', icon: Icons.phone),
            const SizedBox(height: 12),
            _buildTextField(controller: _emailController, label: 'Email', hint: 'Enter email', icon: Icons.email),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity, height: 54,
      child: ElevatedButton(
        onPressed: (_isLoading || _isUploadingLogo || _isUploadingCover) ? null : _createSalon,
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B8B), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        child: _isLoading || _isUploadingLogo || _isUploadingCover
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                const SizedBox(width: 12),
                Text(_isUploadingLogo || _isUploadingCover ? 'Uploading...' : 'Creating...'),
              ])
            : const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_business, size: 20),
                SizedBox(width: 8),
                Text('Create Salon', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ]),
      ),
    );
  }

  void _showImageSourceDialog({required bool isLogo}) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Select Image Source', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Color(0xFFFF6B8B)),
              title: const Text('Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: isLogo ? 800 : 1200);
                if (picked != null) {
                  if (kIsWeb) {
                    final bytes = await picked.readAsBytes();
                    setState(() => isLogo ? _logoWebBytes = bytes : _coverWebBytes = bytes);
                  } else {
                    setState(() => isLogo ? _logoFile = File(picked.path) : _coverFile = File(picked.path));
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Color(0xFFFF6B8B)),
              title: const Text('Camera'),
              onTap: () async {
                Navigator.pop(context);
                final picked = await picker.pickImage(source: ImageSource.camera, maxWidth: isLogo ? 800 : 1200);
                if (picked != null) {
                  if (kIsWeb) {
                    final bytes = await picked.readAsBytes();
                    setState(() => isLogo ? _logoWebBytes = bytes : _coverWebBytes = bytes);
                  } else {
                    setState(() => isLogo ? _logoFile = File(picked.path) : _coverFile = File(picked.path));
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