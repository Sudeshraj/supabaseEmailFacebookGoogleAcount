// screens/owner/age_categories_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/ip_helper.dart';

class AgeCategoriesScreen extends StatefulWidget {
  final int salonId;
  final String salonName;

  const AgeCategoriesScreen({
    super.key,
    required this.salonId,
    required this.salonName,
  });

  @override
  State<AgeCategoriesScreen> createState() => _AgeCategoriesScreenState();
}

class _AgeCategoriesScreenState extends State<AgeCategoriesScreen> {
  // ==================== DATA ====================
  List<Map<String, dynamic>> _ageCategories = [];
  List<Map<String, dynamic>> _globalAgeCategories = [];

  // ==================== UI STATES ====================
  bool _isLoading = true;
  bool _isDeleting = false;
  int? _deletingId;

  // ==================== SUPABASE CLIENT ====================
  final supabase = Supabase.instance.client;

  // ==================== IP ADDRESS ====================
  String? _currentIp;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadIpAddress();
  }

  // ==================== LOAD DATA ====================
  Future<void> _loadIpAddress() async {
    try {
      _currentIp = await IpHelper.getPublicIp();
    } catch (e) {
      debugPrint('❌ Error loading IP: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load salon-specific age categories
      final salonResponse = await supabase
          .from('salon_age_categories')
          .select('''
            id,
            salon_id,
            age_category_id,
            is_active,
            display_order,
            custom_display_name,
            min_age,
            max_age,
            age_categories!salon_age_categories_age_category_id_fkey (
              id,
              name,
              display_name,
              icon_name,
              min_age,
              max_age
            )
          ''')
          .eq('salon_id', widget.salonId)
          .eq('is_active', true)
          .order('display_order');

      // Load global age categories for reference
      final globalResponse = await supabase
          .from('age_categories')
          .select('id, name, display_name, icon_name, min_age, max_age, display_order')
          .eq('is_active', true)
          .order('display_order');

      _globalAgeCategories = List<Map<String, dynamic>>.from(globalResponse);
      _ageCategories = List<Map<String, dynamic>>.from(salonResponse);

      debugPrint('📊 Loaded ${_ageCategories.length} age categories for salon ${widget.salonId}');
    } catch (e) {
      debugPrint('❌ Error loading age categories: $e');
      _showSnackBar('Error loading data: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ==================== LOG ACTIVITY ====================
  Future<void> _logActivity({
    required String actionType,
    required Map<String, dynamic> details,
  }) async {
    try {
      final ownerId = supabase.auth.currentUser?.id;
      if (ownerId == null) return;

      await supabase.from('owner_activity_log').insert({
        'owner_id': ownerId,
        'action_type': actionType,
        'target_type': 'age_category',
        'target_id': details['category_id']?.toString(),
        'details': details,
        'ip_address': _currentIp,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('❌ Error logging activity: $e');
    }
  }

  // ==================== DELETE CATEGORY ====================
  Future<void> _deleteCategory(Map<String, dynamic> category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Age Category'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to delete this age category?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _getAgeIcon(category['age_categories']?['icon_name']),
                    color: Colors.red,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getDisplayName(category),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _getAgeRange(category),
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'This action cannot be undone.',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isDeleting = true;
      _deletingId = category['id'];
    });

    try {
      // Soft delete - set is_active to false
      await supabase
          .from('salon_age_categories')
          .update({'is_active': false})
          .eq('id', category['id']);

      await _logActivity(
        actionType: 'delete_age_category',
        details: {
          'category_id': category['id'],
          'name': _getDisplayName(category),
        },
      );

      _showSnackBar('Age category deleted successfully!', Colors.green);
      await _loadData(); // Refresh list
    } catch (e) {
      debugPrint('❌ Error deleting age category: $e');
      _showSnackBar('Error deleting: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
          _deletingId = null;
        });
      }
    }
  }

  // ==================== EDIT CATEGORY ====================
  void _editCategory(Map<String, dynamic> category) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditAgeCategoryDialog(
        salonId: widget.salonId,
        ageCategory: category,
        globalCategories: _globalAgeCategories,
      ),
    );

    if (result == true) {
      _loadData(); // Refresh after edit
    }
  }

  // ==================== ADD NEW CATEGORY ====================
  void _addCategory() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => EditAgeCategoryDialog(
        salonId: widget.salonId,
        ageCategory: null,
        globalCategories: _globalAgeCategories,
      ),
    );

    if (result == true) {
      _loadData(); // Refresh after add
    }
  }

  // ==================== HELPER METHODS ====================
  String _getDisplayName(Map<String, dynamic> category) {
    final customName = category['custom_display_name'];
    if (customName != null && customName.toString().isNotEmpty) {
      return customName.toString();
    }
    return category['age_categories']?['display_name'] ?? 
           category['age_categories']?['name'] ?? 
           'Unknown';
  }

  String _getAgeRange(Map<String, dynamic> category) {
    final minAge = category['min_age'];
    final maxAge = category['max_age'];
    if (minAge != null && maxAge != null) {
      return '$minAge - $maxAge years';
    }
    // Fallback to global age range if available
    final globalMinAge = category['age_categories']?['min_age'];
    final globalMaxAge = category['age_categories']?['max_age'];
    if (globalMinAge != null && globalMaxAge != null) {
      return '$globalMinAge - $globalMaxAge years';
    }
    return 'Age range not set';
  }

  IconData _getAgeIcon(String? iconName) {
    switch (iconName) {
      case 'child':
        return Icons.child_care;
      case 'teen':
        return Icons.face;
      case 'adult':
        return Icons.person;
      case 'senior':
        return Icons.elderly;
      default:
        return Icons.category;
    }
  }

  Color _getAgeColor(String? iconName) {
    switch (iconName) {
      case 'child':
        return Colors.blue;
      case 'teen':
        return Colors.orange;
      case 'adult':
        return Colors.green;
      case 'senior':
        return Colors.purple;
      default:
        return const Color(0xFFFF6B8B);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ==================== BUILDERS ====================
  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Age Categories',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              widget.salonName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addCategory,
            tooltip: 'Add Age Category',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                  SizedBox(height: 16),
                  Text('Loading age categories...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : _ageCategories.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.category_outlined,
                        size: 80,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Age Categories Found',
                        style: TextStyle(
                          fontSize: isWeb ? 20 : 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Click the + button to add age categories for your salon',
                        style: TextStyle(
                          fontSize: isWeb ? 14 : 12,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _addCategory,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Age Category'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B8B),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Container(
                  color: Colors.grey[50],
                  child: isWeb
                      ? _buildWebLayout()
                      : _buildMobileLayout(),
                ),
    );
  }

  Widget _buildWebLayout() {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.2,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: _ageCategories.length,
      itemBuilder: (context, index) {
        return _buildCategoryCard(_ageCategories[index]);
      },
    );
  }

  Widget _buildMobileLayout() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _ageCategories.length,
      itemBuilder: (context, index) {
        return _buildCategoryListItem(_ageCategories[index]);
      },
    );
  }

  Widget _buildCategoryCard(Map<String, dynamic> category) {
    final iconName = category['age_categories']?['icon_name'];
    final icon = _getAgeIcon(iconName);
    final color = _getAgeColor(iconName);
    final name = _getDisplayName(category);
    final ageRange = _getAgeRange(category);
    final displayOrder = category['display_order'] ?? 0;
    final isDeleting = _isDeleting && _deletingId == category['id'];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () => _editCategory(category),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 32),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '#$displayOrder',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                ageRange,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isDeleting)
                    IconButton(
                      icon: const Icon(Icons.edit, size: 20),
                      onPressed: () => _editCategory(category),
                      color: Colors.grey[600],
                      tooltip: 'Edit',
                    ),
                  if (!isDeleting)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _deleteCategory(category),
                      color: Colors.red,
                      tooltip: 'Delete',
                    ),
                  if (isDeleting)
                    const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryListItem(Map<String, dynamic> category) {
    final iconName = category['age_categories']?['icon_name'];
    final icon = _getAgeIcon(iconName);
    final color = _getAgeColor(iconName);
    final name = _getDisplayName(category);
    final ageRange = _getAgeRange(category);
    final displayOrder = category['display_order'] ?? 0;
    final isDeleting = _isDeleting && _deletingId == category['id'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        onTap: () => _editCategory(category),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ageRange,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            Text(
              'Order: $displayOrder',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
        trailing: isDeleting
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _editCategory(category),
                    color: Colors.grey[600],
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () => _deleteCategory(category),
                    color: Colors.red,
                  ),
                ],
              ),
      ),
    );
  }
}

// ==================== EDIT/ADD DIALOG (FIXED) ====================
class EditAgeCategoryDialog extends StatefulWidget {
  final int salonId;
  final Map<String, dynamic>? ageCategory;
  final List<Map<String, dynamic>> globalCategories;

  const EditAgeCategoryDialog({
    super.key,
    required this.salonId,
    this.ageCategory,
    required this.globalCategories,
  });

  @override
  State<EditAgeCategoryDialog> createState() => _EditAgeCategoryDialogState();
}

class _EditAgeCategoryDialogState extends State<EditAgeCategoryDialog> {
  // ==================== CONTROLLERS ====================
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _minAgeController = TextEditingController();
  final TextEditingController _maxAgeController = TextEditingController();
  final TextEditingController _displayOrderController = TextEditingController();

  // ==================== DATA ====================
  Map<String, dynamic>? _selectedGlobalCategory;
  bool _isCustomName = false;

  // ==================== UI STATES ====================
  bool _isSaving = false;

  // ==================== SUPABASE CLIENT ====================
  final supabase = Supabase.instance.client;

  // ==================== COMPUTED PROPERTIES ====================
  bool get _isEditing => widget.ageCategory != null;

  @override
  void initState() {
    super.initState();
    _loadExistingData();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _minAgeController.dispose();
    _maxAgeController.dispose();
    _displayOrderController.dispose();
    super.dispose();
  }

  void _loadExistingData() {
    if (_isEditing && widget.ageCategory != null) {
      final category = widget.ageCategory!;
      
      // Load global category if exists
      final globalId = category['age_category_id'];
      if (globalId != null) {
        try {
          _selectedGlobalCategory = widget.globalCategories.firstWhere(
            (g) => g['id'] == globalId,
            orElse: () => {}, // This returns {} which is a Map, not null
          );
          // If the result is an empty map, set to null
          if (_selectedGlobalCategory?.isEmpty ?? false) {
            _selectedGlobalCategory = null;
          }
        } catch (e) {
          _selectedGlobalCategory = null;
        }
      }

      // Set custom display name
      final customName = category['custom_display_name'];
      if (customName != null && customName.toString().isNotEmpty) {
        _isCustomName = true;
        _displayNameController.text = customName.toString();
      } else if (_selectedGlobalCategory != null) {
        _displayNameController.text = _selectedGlobalCategory!['display_name']?.toString() ?? '';
      }

      // Set age ranges
      final minAge = category['min_age'];
      final maxAge = category['max_age'];
      if (minAge != null) _minAgeController.text = minAge.toString();
      if (maxAge != null) _maxAgeController.text = maxAge.toString();
      
      // Set display order
      final displayOrder = category['display_order'];
      if (displayOrder != null) _displayOrderController.text = displayOrder.toString();
    } else {
      // Default values for new category
      _displayOrderController.text = '0';
      _minAgeController.text = '0';
      _maxAgeController.text = '100';
      _selectedGlobalCategory = null;
    }
  }

  Future<void> _save() async {
    // Validation
    if (_selectedGlobalCategory == null && !_isCustomName) {
      _showSnackBar('Please select an age category', Colors.red);
      return;
    }

    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty && _selectedGlobalCategory == null) {
      _showSnackBar('Please enter a display name', Colors.red);
      return;
    }

    final minAgeText = _minAgeController.text.trim();
    final maxAgeText = _maxAgeController.text.trim();
    
    if (minAgeText.isEmpty) {
      _showSnackBar('Please enter minimum age', Colors.red);
      return;
    }
    
    if (maxAgeText.isEmpty) {
      _showSnackBar('Please enter maximum age', Colors.red);
      return;
    }

    final minAge = int.tryParse(minAgeText);
    final maxAge = int.tryParse(maxAgeText);
    
    if (minAge == null || maxAge == null) {
      _showSnackBar('Invalid age values', Colors.red);
      return;
    }
    
    if (minAge > maxAge) {
      _showSnackBar('Minimum age cannot be greater than maximum age', Colors.red);
      return;
    }

    final displayOrder = int.tryParse(_displayOrderController.text.trim()) ?? 0;

    setState(() => _isSaving = true);

    try {
      final Map<String, dynamic> data = {
        'salon_id': widget.salonId,
        'is_active': true,
        'display_order': displayOrder,
        'min_age': minAge,
        'max_age': maxAge,
      };

      if (_isCustomName && displayName.isNotEmpty) {
        data['custom_display_name'] = displayName;
        data['age_category_id'] = null;
      } else if (_selectedGlobalCategory != null) {
        data['age_category_id'] = _selectedGlobalCategory!['id'];
        data['custom_display_name'] = null;
      }

      if (_isEditing && widget.ageCategory != null) {
        // Update existing
        await supabase
            .from('salon_age_categories')
            .update(data)
            .eq('id', widget.ageCategory!['id']);
        
        _showSnackBar('Age category updated successfully!', Colors.green);
      } else {
        // Create new
        await supabase
            .from('salon_age_categories')
            .insert(data);
        
        _showSnackBar('Age category created successfully!', Colors.green);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('❌ Error saving age category: $e');
      _showSnackBar('Error saving: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  IconData _getAgeIcon(String? iconName) {
    switch (iconName) {
      case 'child':
        return Icons.child_care;
      case 'teen':
        return Icons.face;
      case 'adult':
        return Icons.person;
      case 'senior':
        return Icons.elderly;
      default:
        return Icons.category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 800;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: isWeb ? 500 : double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _isEditing ? Icons.edit : Icons.add,
                      color: const Color(0xFFFF6B8B),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Edit Age Category' : 'Add Age Category',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Global Category Selection
              if (!_isCustomName) ...[
                const Text(
                  'Base Age Category',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<Map<String, dynamic>>(
                  initialValue: _selectedGlobalCategory,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  items: widget.globalCategories.map((category) {
                    return DropdownMenuItem(
                      value: category,
                      child: Row(
                        children: [
                          Icon(
                            _getAgeIcon(category['icon_name']),
                            size: 20,
                            color: const Color(0xFFFF6B8B),
                          ),
                          const SizedBox(width: 12),
                          Text(category['display_name'] ?? category['name'] ?? 'Unknown'),
                          const SizedBox(width: 8),
                          Text(
                            '(${category['min_age'] ?? 0}-${category['max_age'] ?? 100} yrs)',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (Map<String, dynamic>? value) {
                    setState(() {
                      _selectedGlobalCategory = value;
                      if (value != null && !_isCustomName) {
                        _displayNameController.text = value['display_name']?.toString() ?? '';
                        _minAgeController.text = value['min_age']?.toString() ?? '0';
                        _maxAgeController.text = value['max_age']?.toString() ?? '100';
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                
                // Custom Name Option
                Row(
                  children: [
                    Checkbox(
                      value: _isCustomName,
                      onChanged: (bool? value) {
                        setState(() {
                          _isCustomName = value ?? false;
                          if (!_isCustomName && _selectedGlobalCategory != null) {
                            _displayNameController.text = _selectedGlobalCategory!['display_name']?.toString() ?? '';
                          }
                        });
                      },
                      activeColor: const Color(0xFFFF6B8B),
                    ),
                    const Text('Use custom display name'),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Custom Display Name
              if (_isCustomName || _isEditing) ...[
                TextField(
                  controller: _displayNameController,
                  decoration: InputDecoration(
                    labelText: 'Display Name',
                    hintText: 'e.g., Children, Adults, Seniors',
                    prefixIcon: const Icon(Icons.title, color: Color(0xFFFF6B8B)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFFF6B8B), width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Age Range
              const Text(
                'Age Range',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minAgeController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Minimum Age',
                        hintText: '0',
                        prefixIcon: const Icon(Icons.arrow_downward, color: Color(0xFFFF6B8B)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Icon(Icons.arrow_forward, color: Colors.grey),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _maxAgeController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Maximum Age',
                        hintText: '100',
                        prefixIcon: const Icon(Icons.arrow_upward, color: Color(0xFFFF6B8B)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Display Order
              TextField(
                controller: _displayOrderController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Display Order',
                  hintText: '0',
                  helperText: 'Lower numbers appear first',
                  prefixIcon: const Icon(Icons.sort, color: Color(0xFFFF6B8B)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B8B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(_isEditing ? 'Update' : 'Create'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}