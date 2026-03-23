import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';

class AddGenderScreen extends StatefulWidget {
  const AddGenderScreen({super.key});

  @override
  State<AddGenderScreen> createState() => _AddGenderScreenState();
}

class _AddGenderScreenState extends State<AddGenderScreen> {
  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _iconNameController = TextEditingController();

  // Variables
  bool _isActive = true;
  int _displayOrder = 0;
  bool _isLoading = false;
  bool _isLoadingData = true;
  bool _isCheckingName = false;
  String? _nameError;
  List<String> _suggestions = [];
  
  // All existing genders (for duplicate check)
  List<String> _existingGenders = [];

  // Available icons for suggestions
  final List<String> _suggestedIcons = [
    'male',
    'female',
    'unisex',
    'man',
    'woman',
    'person',
    'transgender',
    'wc',
    'people',
  ];

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadMaxDisplayOrder();
    _loadExistingGenders();
    
    // Add listener for name changes
    _nameController.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _displayNameController.dispose();
    _iconNameController.dispose();
    super.dispose();
  }

  // Load existing genders for duplicate check
  Future<void> _loadExistingGenders() async {
    try {
      final response = await supabase
          .from('genders')
          .select('name');
      
      setState(() {
        _existingGenders = response
            .map((e) => e['name'].toString().toLowerCase())
            .toList();
      });
    } catch (e) {
      debugPrint('❌ Error loading existing genders: $e');
    }
  }

  // Check if gender name exists
  Future<bool> _isGenderNameExists(String name) async {
    if (name.isEmpty) return false;
    
    final normalizedName = name.trim().toLowerCase();
    return _existingGenders.contains(normalizedName);
  }

  // Get suggestions based on input
  List<String> _getSuggestions(String input) {
    if (input.isEmpty) return [];
    
    final normalizedInput = input.trim().toLowerCase();
    if (normalizedInput.isEmpty) return [];
    
    // Common gender names for suggestions
    final commonGenders = [
      'male', 'female', 'unisex',
      'man', 'woman', 'non-binary',
      'transgender', 'gender-neutral',
      'prefer-not-to-say'
    ];
    
    // Filter suggestions that start with input
    final suggestions = commonGenders.where((gender) {
      return gender.toLowerCase().contains(normalizedInput) && 
             !_existingGenders.contains(gender.toLowerCase());
    }).toList();
    
    return suggestions.take(5).toList();
  }

  // Handle name change
  void _onNameChanged() async {
    final input = _nameController.text;
    
    if (input.isEmpty) {
      setState(() {
        _suggestions = [];
        _nameError = null;
        _isCheckingName = false;
      });
      return;
    }
    
    // Update suggestions
    setState(() {
      _suggestions = _getSuggestions(input);
    });
    
    // Check for duplicate (with debounce)
    _checkDuplicateName(input);
  }
  
  // Check duplicate with debounce
  Timer? _debounceTimer;
  void _checkDuplicateName(String name) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      if (name.trim().isEmpty) {
        setState(() {
          _nameError = null;
          _isCheckingName = false;
        });
        return;
      }
      
      setState(() => _isCheckingName = true);
      
      final exists = await _isGenderNameExists(name);
      
      if (mounted) {
        setState(() {
          _isCheckingName = false;
          if (exists) {
            _nameError = 'Gender name already exists';
          } else {
            _nameError = null;
          }
        });
      }
    });
  }

  // Load max display order to set default
  Future<void> _loadMaxDisplayOrder() async {
    try {
      final response = await supabase
          .from('genders')
          .select('display_order')
          .order('display_order', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        final maxOrder = response[0]['display_order'] as int? ?? 0;
        setState(() {
          _displayOrder = maxOrder + 1;
          _isLoadingData = false;
        });
      } else {
        setState(() {
          _displayOrder = 1;
          _isLoadingData = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading max display order: $e');
      setState(() {
        _displayOrder = 1;
        _isLoadingData = false;
      });
    }
  }

  // Create gender
  Future<void> _createGender() async {
    final name = _nameController.text.trim();
    
    if (name.isEmpty) {
      _showSnackBar('Gender name is required', Colors.red);
      return;
    }
    
    // Check duplicate again before saving
    final exists = await _isGenderNameExists(name);
    if (exists) {
      _showSnackBar('Gender name already exists', Colors.red);
      return;
    }

    if (_displayNameController.text.trim().isEmpty) {
      _showSnackBar('Display name is required', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final genderData = {
        'name': name.toLowerCase(),
        'display_name': _displayNameController.text.trim(),
        'icon_name': _iconNameController.text.trim().isEmpty 
            ? name.toLowerCase() 
            : _iconNameController.text.trim(),
        'display_order': _displayOrder,
        'is_active': _isActive,
      };

      debugPrint('📝 Creating gender: ${genderData['name']}');

      await supabase
          .from('genders')
          .insert(genderData)
          .select()
          .single();

      debugPrint('✅ Gender created');

      if (!mounted) return;

      await showCustomAlert(
        context: context,
        title: "🎉 Gender Added!",
        message: "${_displayNameController.text.trim()} gender has been added successfully.",
        isError: false,
      );

      if (!mounted) return;
      Navigator.pop(context, true);

    } catch (e) {
      debugPrint('❌ Error creating gender: $e');
      if (mounted) {
        _showSnackBar('Error creating gender: $e', Colors.red);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  // Auto-fill display name based on name
  void _autoFillDisplayName() {
    final name = _nameController.text.trim().toLowerCase();
    if (name.isEmpty) return;
    
    String displayName;
    switch (name) {
      case 'male':
        displayName = '👨 Male';
        break;
      case 'female':
        displayName = '👩 Female';
        break;
      case 'unisex':
        displayName = '👤 Unisex';
        break;
      case 'man':
        displayName = '👨 Man';
        break;
      case 'woman':
        displayName = '👩 Woman';
        break;
      case 'non-binary':
        displayName = '👤 Non-Binary';
        break;
      default:
        displayName = '${name[0].toUpperCase()}${name.substring(1)}';
    }
    
    setState(() {
      _displayNameController.text = displayName;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add New Gender'),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        elevation: 0,
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF6B8B)))
          : Container(
              color: Colors.grey[50],
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isWeb ? 800 : double.infinity),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isWeb ? 32 : 16),
                    child: Card(
                      elevation: isWeb ? 4 : 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(isWeb ? 32 : 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 32),
                            _buildForm(),
                            const SizedBox(height: 32),
                            _buildCreateButton(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

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
              Icons.wc,
              color: Color(0xFFFF6B8B),
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Add New Gender',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new gender option for your salon',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Gender Name (Required)
        const Text(
          'Gender Name *',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: 'e.g., male, female, unisex',
            prefixIcon: const Icon(Icons.wc, color: Colors.grey),
            suffixIcon: _isCheckingName
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _nameError == null
                    ? null
                    : const Icon(Icons.error, color: Colors.red),
            errorText: _nameError,
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
        ),
        
        // Suggestions
        if (_suggestions.isNotEmpty && _nameError == null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _suggestions.map((suggestion) {
                return ActionChip(
                  label: Text(suggestion),
                  onPressed: () {
                    setState(() {
                      _nameController.text = suggestion;
                      _suggestions = [];
                    });
                    _autoFillDisplayName();
                  },
                  backgroundColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                  labelStyle: const TextStyle(color: Color(0xFFFF6B8B)),
                );
              }).toList(),
            ),
          ),
        
        const SizedBox(height: 16),

        // Display Name (Required)
        const Text(
          'Display Name *',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _displayNameController,
          decoration: InputDecoration(
            hintText: 'e.g., 👨 Male, 👩 Female, 👤 Unisex',
            prefixIcon: const Icon(Icons.badge, color: Colors.grey),
            suffixIcon: IconButton(
              icon: const Icon(Icons.auto_awesome, size: 18),
              onPressed: _autoFillDisplayName,
              tooltip: 'Auto-fill from name',
              color: const Color(0xFFFF6B8B),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'How this gender will appear to customers (use emojis if desired)',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        const SizedBox(height: 16),

        // Icon Name
        const Text(
          'Icon Name',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _iconNameController,
          decoration: InputDecoration(
            hintText: 'e.g., male, female, unisex',
            prefixIcon: const Icon(Icons.abc, color: Colors.grey),
            suffixIcon: PopupMenuButton<String>(
              icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
              onSelected: (value) {
                setState(() {
                  _iconNameController.text = value;
                });
              },
              itemBuilder: (context) {
                return _suggestedIcons.map((icon) {
                  return PopupMenuItem(
                    value: icon,
                    child: Row(
                      children: [
                        Icon(Icons.abc, size: 16, color: const Color(0xFFFF6B8B)),
                        const SizedBox(width: 8),
                        Text(icon),
                      ],
                    ),
                  );
                }).toList();
              },
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Material Icons name. Click dropdown for suggestions',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        const SizedBox(height: 16),

        // Display Order
        const Text(
          'Display Order',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: TextEditingController(text: _displayOrder.toString()),
          keyboardType: TextInputType.number,
          onChanged: (value) {
            final intValue = int.tryParse(value);
            if (intValue != null) {
              setState(() {
                _displayOrder = intValue;
              });
            }
          },
          decoration: InputDecoration(
            hintText: 'Order in which gender appears',
            prefixIcon: const Icon(Icons.sort, color: Colors.grey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Active Status
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Active',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Inactive genders will not be shown to customers',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Switch(
              value: _isActive,
              onChanged: (value) {
                setState(() {
                  _isActive = value;
                });
              },
              activeTrackColor: const Color(0xFFFF6B8B),
              activeThumbColor: Colors.white,
              inactiveThumbColor: Colors.grey[400],
              inactiveTrackColor: Colors.grey[300],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCreateButton() {
    final isDisabled = _isLoading || 
        _nameError != null || 
        _nameController.text.trim().isEmpty ||
        _displayNameController.text.trim().isEmpty;
    
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isDisabled ? null : _createGender,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFF6B8B),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: _isLoading
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text('Creating...'),
                ],
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Create Gender',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }
}