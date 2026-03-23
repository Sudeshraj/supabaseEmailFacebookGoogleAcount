import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/alertBox/show_custom_alert.dart';

class AddAgeCategoryScreen extends StatefulWidget {
  const AddAgeCategoryScreen({super.key});

  @override
  State<AddAgeCategoryScreen> createState() => _AddAgeCategoryScreenState();
}

class _AddAgeCategoryScreenState extends State<AddAgeCategoryScreen> {
  // Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _iconNameController = TextEditingController();
  final TextEditingController _minAgeController = TextEditingController();
  final TextEditingController _maxAgeController = TextEditingController();

  // Variables
  bool _isActive = true;
  int _displayOrder = 0;
  bool _isLoading = false;
  bool _isLoadingData = true;
  bool _isCheckingName = false;
  String? _nameError;
  String? _ageRangeError;
  List<String> _suggestions = [];
  
  // All existing age categories (for duplicate check)
  List<String> _existingAgeCategories = [];

  // Available icons for suggestions
  final List<String> _suggestedIcons = [
    'child',
    'teen',
    'adult',
    'senior',
    'cake',
    'calendar_today',
    'timeline',
    'accessibility',
    'person',
    'group',
  ];

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadMaxDisplayOrder();
    _loadExistingAgeCategories();
    
    // Add listener for name changes
    _nameController.addListener(_onNameChanged);
    
    // Add listeners for age range validation
    _minAgeController.addListener(_validateAgeRange);
    _maxAgeController.addListener(_validateAgeRange);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _minAgeController.removeListener(_validateAgeRange);
    _maxAgeController.removeListener(_validateAgeRange);
    _nameController.dispose();
    _displayNameController.dispose();
    _iconNameController.dispose();
    _minAgeController.dispose();
    _maxAgeController.dispose();
    super.dispose();
  }

  // Load existing age categories for duplicate check
  Future<void> _loadExistingAgeCategories() async {
    try {
      final response = await supabase
          .from('age_categories')
          .select('name');
      
      setState(() {
        _existingAgeCategories = response
            .map((e) => e['name'].toString().toLowerCase())
            .toList();
      });
    } catch (e) {
      debugPrint('❌ Error loading existing age categories: $e');
    }
  }

  // Check if age category name exists
  Future<bool> _isAgeCategoryNameExists(String name) async {
    if (name.isEmpty) return false;
    
    final normalizedName = name.trim().toLowerCase();
    return _existingAgeCategories.contains(normalizedName);
  }

  // Validate age range
  void _validateAgeRange() {
    final minAgeStr = _minAgeController.text.trim();
    final maxAgeStr = _maxAgeController.text.trim();
    
    if (minAgeStr.isEmpty || maxAgeStr.isEmpty) {
      setState(() {
        _ageRangeError = null;
      });
      return;
    }
    
    final minAge = int.tryParse(minAgeStr);
    final maxAge = int.tryParse(maxAgeStr);
    
    if (minAge == null || maxAge == null) {
      setState(() {
        _ageRangeError = 'Please enter valid numbers';
      });
      return;
    }
    
    if (minAge < 0) {
      setState(() {
        _ageRangeError = 'Minimum age cannot be negative';
      });
      return;
    }
    
    if (maxAge > 120) {
      setState(() {
        _ageRangeError = 'Maximum age cannot exceed 120';
      });
      return;
    }
    
    if (minAge > maxAge) {
      setState(() {
        _ageRangeError = 'Minimum age cannot be greater than maximum age';
      });
      return;
    }
    
    setState(() {
      _ageRangeError = null;
    });
  }

  // Get suggestions based on input
  List<String> _getSuggestions(String input) {
    if (input.isEmpty) return [];
    
    final normalizedInput = input.trim().toLowerCase();
    if (normalizedInput.isEmpty) return [];
    
    // Common age category names for suggestions
    final commonAgeCategories = [
      'child', 'children', 'kid', 'kids',
      'teen', 'teenager', 'adolescent', 'youth',
      'adult', 'adults', 'young adult', 'middle age',
      'senior', 'elder', 'old', 'mature',
      'infant', 'baby', 'toddler', 'pre-school',
      'school age', 'pre-teen', 'young', 'all ages'
    ];
    
    // Filter suggestions that contain input
    final suggestions = commonAgeCategories.where((ageCat) {
      return ageCat.toLowerCase().contains(normalizedInput) && 
             !_existingAgeCategories.contains(ageCat.toLowerCase());
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
      
      final exists = await _isAgeCategoryNameExists(name);
      
      if (mounted) {
        setState(() {
          _isCheckingName = false;
          if (exists) {
            _nameError = 'Age category name already exists';
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
          .from('age_categories')
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

  // Auto-fill display name based on name and age range
  void _autoFillDisplayName() {
    final name = _nameController.text.trim().toLowerCase();
    final minAge = _minAgeController.text.trim();
    final maxAge = _maxAgeController.text.trim();
    
    if (name.isEmpty) return;
    
    String displayName;
    switch (name) {
      case 'child':
      case 'children':
      case 'kid':
      case 'kids':
        displayName = '👶 Child';
        break;
      case 'teen':
      case 'teenager':
      case 'adolescent':
      case 'youth':
        displayName = '🧑 Teen';
        break;
      case 'adult':
      case 'adults':
      case 'young adult':
        displayName = '👨 Adult';
        break;
      case 'senior':
      case 'elder':
      case 'old':
        displayName = '👴 Senior';
        break;
      case 'infant':
      case 'baby':
        displayName = '🍼 Baby';
        break;
      case 'toddler':
        displayName = '🚼 Toddler';
        break;
      case 'all ages':
      case 'everyone':
        displayName = '👥 All Ages';
        break;
      default:
        displayName = '${name[0].toUpperCase()}${name.substring(1)}';
    }
    
    // Add age range if available
    if (minAge.isNotEmpty && maxAge.isNotEmpty) {
      displayName = '$displayName ($minAge-$maxAge yrs)';
    }
    
    setState(() {
      _displayNameController.text = displayName;
    });
  }

  // Auto-fill age range based on name
  void _autoFillAgeRange() {
    final name = _nameController.text.trim().toLowerCase();
    
    switch (name) {
      case 'child':
      case 'children':
      case 'kid':
      case 'kids':
        _minAgeController.text = '0';
        _maxAgeController.text = '12';
        break;
      case 'teen':
      case 'teenager':
      case 'adolescent':
      case 'youth':
        _minAgeController.text = '13';
        _maxAgeController.text = '19';
        break;
      case 'adult':
      case 'adults':
        _minAgeController.text = '20';
        _maxAgeController.text = '60';
        break;
      case 'senior':
      case 'elder':
      case 'old':
        _minAgeController.text = '61';
        _maxAgeController.text = '120';
        break;
      case 'infant':
      case 'baby':
        _minAgeController.text = '0';
        _maxAgeController.text = '1';
        break;
      case 'toddler':
        _minAgeController.text = '1';
        _maxAgeController.text = '3';
        break;
      case 'all ages':
      case 'everyone':
        _minAgeController.text = '0';
        _maxAgeController.text = '120';
        break;
      default:
        // Don't auto-fill if not recognized
        break;
    }
    
    _validateAgeRange();
  }

  // Create age category
  Future<void> _createAgeCategory() async {
    final name = _nameController.text.trim();
    
    if (name.isEmpty) {
      _showSnackBar('Age category name is required', Colors.red);
      return;
    }
    
    // Check duplicate again before saving
    final exists = await _isAgeCategoryNameExists(name);
    if (exists) {
      _showSnackBar('Age category name already exists', Colors.red);
      return;
    }

    if (_displayNameController.text.trim().isEmpty) {
      _showSnackBar('Display name is required', Colors.red);
      return;
    }

    final minAgeStr = _minAgeController.text.trim();
    final maxAgeStr = _maxAgeController.text.trim();
    
    if (minAgeStr.isEmpty || maxAgeStr.isEmpty) {
      _showSnackBar('Age range is required', Colors.red);
      return;
    }
    
    final minAge = int.tryParse(minAgeStr);
    final maxAge = int.tryParse(maxAgeStr);
    
    if (minAge == null || maxAge == null) {
      _showSnackBar('Please enter valid numbers for age range', Colors.red);
      return;
    }
    
    if (minAge > maxAge) {
      _showSnackBar('Minimum age cannot be greater than maximum age', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final ageCategoryData = {
        'name': name.toLowerCase(),
        'display_name': _displayNameController.text.trim(),
        'min_age': minAge,
        'max_age': maxAge,
        'icon_name': _iconNameController.text.trim().isEmpty 
            ? name.toLowerCase() 
            : _iconNameController.text.trim(),
        'display_order': _displayOrder,
        'is_active': _isActive,
      };

      debugPrint('📝 Creating age category: ${ageCategoryData['name']}');
      debugPrint('   Age range: ${ageCategoryData['min_age']} - ${ageCategoryData['max_age']}');

      await supabase
          .from('age_categories')
          .insert(ageCategoryData)
          .select()
          .single();

      debugPrint('✅ Age category created');

      if (!mounted) return;

      await showCustomAlert(
        context: context,
        title: "🎉 Age Category Added!",
        message: "${_displayNameController.text.trim()} age category has been added successfully.\n\n"
            "Age Range: $minAge - $maxAge years",
        isError: false,
      );

      if (!mounted) return;
      Navigator.pop(context, true);

    } catch (e) {
      debugPrint('❌ Error creating age category: $e');
      if (mounted) {
        _showSnackBar('Error creating age category: $e', Colors.red);
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

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Age Category'),
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
              Icons.timeline,
              color: Color(0xFFFF6B8B),
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Add Age Category',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a new age group for your salon services',
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
        // Age Category Name (Required)
        const Text(
          'Age Category Name *',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: 'e.g., child, teen, adult, senior',
            prefixIcon: const Icon(Icons.category, color: Colors.grey),
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
                    _autoFillAgeRange();
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
            hintText: 'e.g., 👶 Child, 🧑 Teen, 👨 Adult, 👴 Senior',
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
          'How this age group will appear to customers (use emojis if desired)',
          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
        ),
        const SizedBox(height: 16),

        // Age Range (Min and Max)
        const Text(
          'Age Range *',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _minAgeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Min Age',
                  prefixIcon: const Icon(Icons.arrow_downward, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  errorText: _ageRangeError != null && _minAgeController.text.isNotEmpty ? null : null,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text('to', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _maxAgeController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Max Age',
                  prefixIcon: const Icon(Icons.arrow_upward, size: 18),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  errorText: _ageRangeError != null && _maxAgeController.text.isNotEmpty ? null : null,
                ),
              ),
            ),
          ],
        ),
        if (_ageRangeError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _ageRangeError!,
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Age range in years (e.g., 0-12 for children, 13-19 for teens)',
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
            hintText: 'e.g., child, teen, adult, senior',
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
            hintText: 'Order in which age category appears',
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
                    'Inactive age categories will not be shown to customers',
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
        _ageRangeError != null ||
        _nameController.text.trim().isEmpty ||
        _displayNameController.text.trim().isEmpty ||
        _minAgeController.text.trim().isEmpty ||
        _maxAgeController.text.trim().isEmpty;
    
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: isDisabled ? null : _createAgeCategory,
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
                    'Create Age Category',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }
}