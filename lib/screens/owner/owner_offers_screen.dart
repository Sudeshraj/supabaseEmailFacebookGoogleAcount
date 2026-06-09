import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/notification_service.dart';

class OwnerOffersScreen extends StatefulWidget {
  final String? salonId;
  
  const OwnerOffersScreen({super.key, this.salonId});

  @override
  State<OwnerOffersScreen> createState() => _OwnerOffersScreenState();
}

class _OwnerOffersScreenState extends State<OwnerOffersScreen> {
  final supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();
  
  List<Map<String, dynamic>> _offers = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  int? _currentSalonId;
  String? _currentSalonName;
  
  // Filter
  String _selectedFilter = 'active'; // active, expired, all
  
  // Notification option for new offer
  bool _sendNotificationToFollowers = true;
  
  @override
  void initState() {
    super.initState();
    _loadSalonAndOffers();
  }
  
  Future<void> _loadSalonAndOffers() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = 'Please login to continue';
          _isLoading = false;
        });
        return;
      }
      
      // If salonId is passed via route, use it
      if (widget.salonId != null && widget.salonId!.isNotEmpty) {
        final salonResult = await supabase
            .from('salons')
            .select('id, name')
            .eq('id', int.parse(widget.salonId!))
            .eq('owner_id', user.id)
            .maybeSingle();
        
        if (salonResult != null) {
          setState(() {
            _currentSalonId = salonResult['id'] as int;
            _currentSalonName = salonResult['name'];
          });
          await _loadOffers();
          return;
        }
      }
      
      // Get owner's first salon
      final salonResult = await supabase
          .from('salons')
          .select('id, name')
          .eq('owner_id', user.id)
          .maybeSingle();
      
      if (salonResult == null) {
        if (!mounted) return;
        setState(() {
          _hasError = true;
          _errorMessage = 'You don\'t own any salon';
          _isLoading = false;
        });
        return;
      }
      
      setState(() {
        _currentSalonId = salonResult['id'] as int;
        _currentSalonName = salonResult['name'];
      });
      
      await _loadOffers();
      
    } catch (e) {
      debugPrint('Error loading salon: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load salon data';
        _isLoading = false;
      });
    }
  }
  
  Future<void> _loadOffers() async {
    // ✅ Fix: Use local variable to avoid type promotion issue
    final salonId = _currentSalonId;
    if (salonId == null) return;
    
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    
    try {
      final result = await supabase
          .from('offers')
          .select('''
            id,
            title,
            description,
            discount_type,
            discount_value,
            points_required,
            valid_from,
            valid_to,
            image_url,
            is_active,
            usage_limit,
            used_count,
            created_at
          ''')
          .eq('salon_id', salonId)  // ✅ Use local variable
          .order('created_at', ascending: false);
      
      if (!mounted) return;
      setState(() {
        _offers = List<Map<String, dynamic>>.from(result);
        _isLoading = false;
      });
      
    } catch (e) {
      debugPrint('Error loading offers: $e');
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load offers';
        _isLoading = false;
      });
    }
  }
  
  List<Map<String, dynamic>> get _filteredOffers {
    final now = DateTime.now();
    
    if (_selectedFilter == 'active') {
      return _offers.where((offer) {
        final validTo = DateTime.parse(offer['valid_to']);
        return offer['is_active'] == true && validTo.isAfter(now);
      }).toList();
    } else if (_selectedFilter == 'expired') {
      return _offers.where((offer) {
        final validTo = DateTime.parse(offer['valid_to']);
        return validTo.isBefore(now) || offer['is_active'] == false;
      }).toList();
    }
    return _offers;
  }
  
  Future<void> _createOffer() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => OfferFormDialog(
        isEditing: false,
        sendNotificationToFollowers: _sendNotificationToFollowers,
        onNotificationToggle: (value) {
          _sendNotificationToFollowers = value;
        },
      ),
    );
    
    if (result != null && mounted) {
      await _saveOffer(result);
    }
  }
  
  Future<void> _editOffer(Map<String, dynamic> offer) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => OfferFormDialog(
        isEditing: true,
        offer: offer,
        sendNotificationToFollowers: false,
        onNotificationToggle: (value) {},
      ),
    );
    
    if (result != null && mounted) {
      await _updateOffer(offer['id'], result);
    }
  }
  
  Future<void> _saveOffer(Map<String, dynamic> offerData) async {
    // ✅ Fix: Use local variable to avoid type promotion issue
    final salonId = _currentSalonId;
    if (salonId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Insert offer
      final result = await supabase.from('offers').insert({
        'salon_id': salonId,  // ✅ Use local variable
        'title': offerData['title'],
        'description': offerData['description'],
        'discount_type': offerData['discount_type'],
        'discount_value': offerData['discount_value'],
        'points_required': offerData['points_required'] ?? 0,
        'valid_from': offerData['valid_from'],
        'valid_to': offerData['valid_to'],
        'image_url': offerData['image_url'],
        'is_active': true,
        'usage_limit': offerData['usage_limit'],
        'used_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      }).select();
      
      // Send notifications to followers if enabled
      if (offerData['send_notification'] == true && result.isNotEmpty) {
        await _sendOfferNotificationsToFollowers(result.first);
      }
      
      await _loadOffers();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offer created successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      
    } catch (e) {
      debugPrint('Error creating offer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _sendOfferNotificationsToFollowers(Map<String, dynamic> offer) async {
    // ✅ Fix: Use local variable
    final salonId = _currentSalonId;
    if (salonId == null) return;
    
    try {
      // Get all followers of this salon
      final followers = await supabase
          .from('salon_followers')
          .select('customer_id')
          .eq('salon_id', salonId);  // ✅ Use local variable
      
      if (followers.isEmpty) {
        debugPrint('No followers to notify');
        return;
      }
      
      String discountText = '';
      if (offer['discount_type'] == 'percentage') {
        discountText = '${offer['discount_value']}% OFF';
      } else if (offer['discount_type'] == 'fixed') {
        discountText = 'Rs. ${offer['discount_value']} OFF';
      } else {
        discountText = 'FREE SERVICE';
      }
      
      // Send notification to each follower
      for (var follower in followers) {
        await _notificationService.sendSpecialOffer(
          customerId: follower['customer_id'],
          offerTitle: offer['title'],
          offerDescription: offer['description'] ?? '',
          discountText: discountText,
          offerId: offer['id'],
          salonName: _currentSalonName ?? 'Salon',
        );
      }
      
      debugPrint('✅ Sent notifications to ${followers.length} followers');
      
    } catch (e) {
      debugPrint('Error sending notifications: $e');
    }
  }
  
  Future<void> _updateOffer(int offerId, Map<String, dynamic> offerData) async {
    setState(() => _isLoading = true);
    
    try {
      await supabase
          .from('offers')
          .update({
            'title': offerData['title'],
            'description': offerData['description'],
            'discount_type': offerData['discount_type'],
            'discount_value': offerData['discount_value'],
            'points_required': offerData['points_required'] ?? 0,
            'valid_from': offerData['valid_from'],
            'valid_to': offerData['valid_to'],
            'image_url': offerData['image_url'],
            'usage_limit': offerData['usage_limit'],
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', offerId);
      
      await _loadOffers();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offer updated successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      
    } catch (e) {
      debugPrint('Error updating offer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _toggleOfferStatus(int offerId, bool isActive) async {
    setState(() => _isLoading = true);
    
    try {
      await supabase
          .from('offers')
          .update({
            'is_active': !isActive,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', offerId);
      
      await _loadOffers();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!isActive ? 'Offer activated' : 'Offer deactivated'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      
    } catch (e) {
      debugPrint('Error toggling offer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  Future<void> _deleteOffer(int offerId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Offer'),
        content: const Text('Are you sure you want to delete this offer? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    setState(() => _isLoading = true);
    
    try {
      await supabase.from('offers').delete().eq('id', offerId);
      await _loadOffers();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offer deleted successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      
    } catch (e) {
      debugPrint('Error deleting offer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  String _getDiscountText(Map<String, dynamic> offer) {
    if (offer['discount_type'] == 'percentage') {
      return '${offer['discount_value']}% OFF';
    } else if (offer['discount_type'] == 'fixed') {
      return 'Rs. ${offer['discount_value']} OFF';
    } else {
      return 'FREE SERVICE';
    }
  }
  
  Color _getStatusColor(Map<String, dynamic> offer) {
    final now = DateTime.now();
    final validTo = DateTime.parse(offer['valid_to']);
    final isExpired = validTo.isBefore(now);
    
    if (!offer['is_active']) {
      return Colors.grey;
    } else if (isExpired) {
      return Colors.red;
    } else {
      return Colors.green;
    }
  }
  
  String _getStatusText(Map<String, dynamic> offer) {
    final now = DateTime.now();
    final validTo = DateTime.parse(offer['valid_to']);
    final isExpired = validTo.isBefore(now);
    
    if (!offer['is_active']) {
      return 'Inactive';
    } else if (isExpired) {
      return 'Expired';
    } else {
      final daysLeft = validTo.difference(now).inDays;
      return 'Active • $daysLeft days left';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final activeCount = _offers.where((o) {
      final validTo = DateTime.parse(o['valid_to']);
      return o['is_active'] == true && validTo.isAfter(DateTime.now());
    }).length;
    
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manage Offers',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            if (_currentSalonName != null)
              Text(
                _currentSalonName!,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createOffer,
            tooltip: 'Add Offer',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOffers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading && _offers.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFFFF6B8B)),
                  SizedBox(height: 16),
                  Text('Loading offers...'),
                ],
              ),
            )
          : _hasError
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage,
                        style: TextStyle(color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _loadSalonAndOffers,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B8B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Salon Info Card
                    Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.local_offer,
                              color: Color(0xFFFF6B8B),
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentSalonName ?? 'Loading...',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Total Offers: ${_offers.length} | Active: $activeCount',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 14, color: Colors.green[700]),
                                const SizedBox(width: 4),
                                Text(
                                  'Your Salon',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Filter Chips
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          _buildFilterChip('All Offers', 'all'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Active', 'active'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Expired/Inactive', 'expired'),
                        ],
                      ),
                    ),
                    
                    // Offers List
                    Expanded(
                      child: _filteredOffers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.local_offer_outlined,
                                      size: 64,
                                      color: const Color(0xFFFF6B8B).withValues(alpha: 0.5),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    _selectedFilter == 'active'
                                        ? 'No Active Offers'
                                        : _selectedFilter == 'expired'
                                        ? 'No Expired Offers'
                                        : 'No Offers Yet',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _selectedFilter == 'all' && _offers.isEmpty
                                        ? 'Tap the + button to create your first offer'
                                        : 'Try changing the filter',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  if (_offers.isEmpty)
                                    ElevatedButton.icon(
                                      onPressed: _createOffer,
                                      icon: const Icon(Icons.add),
                                      label: const Text('Create Offer'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFFF6B8B),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _filteredOffers.length,
                              itemBuilder: (context, index) {
                                final offer = _filteredOffers[index];
                                return _buildOfferCard(offer);
                              },
                            ),
                    ),
                  ],
                ),
      );
  }
  
  Widget _buildFilterChip(String label, String value) {
    return FilterChip(
      label: Text(label),
      selected: _selectedFilter == value,
      onSelected: (selected) {
        setState(() {
          _selectedFilter = value;
        });
      },
      selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
      checkmarkColor: const Color(0xFFFF6B8B),
      labelStyle: TextStyle(
        color: _selectedFilter == value ? const Color(0xFFFF6B8B) : Colors.grey[600],
        fontWeight: _selectedFilter == value ? FontWeight.w600 : FontWeight.normal,
      ),
      shape: StadiumBorder(
        side: BorderSide(
          color: _selectedFilter == value ? const Color(0xFFFF6B8B) : Colors.grey[300]!,
        ),
      ),
    );
  }
  
  Widget _buildOfferCard(Map<String, dynamic> offer) {
    final statusColor = _getStatusColor(offer);
    final statusText = _getStatusText(offer);
    final discountText = _getDiscountText(offer);
    final validFrom = DateFormat('MMM dd, yyyy').format(DateTime.parse(offer['valid_from']));
    final validTo = DateFormat('MMM dd, yyyy').format(DateTime.parse(offer['valid_to']));
    final usageLeft = offer['usage_limit'] != null 
        ? (offer['usage_limit'] - (offer['used_count'] ?? 0))
        : null;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _editOffer(offer),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status
              Row(
                children: [
                  // Discount badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [const Color(0xFFFF6B8B), const Color(0xFFFF6B8B).withValues(alpha: 0.7)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      discountText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10,
                            color: statusColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Title
              Text(
                offer['title'],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              
              // Description
              Text(
                offer['description'] ?? '',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              
              // Points and validity
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  if ((offer['points_required'] ?? 0) > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${offer['points_required']} points',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          '$validFrom - $validTo',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  
                  if (usageLeft != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people, size: 12, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(
                            '$usageLeft uses left',
                            style: TextStyle(fontSize: 11, color: Colors.blue[700]),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Toggle Active/Inactive button
                  OutlinedButton.icon(
                    onPressed: () => _toggleOfferStatus(offer['id'], offer['is_active']),
                    icon: Icon(
                      offer['is_active'] ? Icons.pause : Icons.play_arrow,
                      size: 16,
                    ),
                    label: Text(
                      offer['is_active'] ? 'Deactivate' : 'Activate',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: offer['is_active'] ? Colors.orange : Colors.green,
                      side: BorderSide(
                        color: offer['is_active'] ? Colors.orange : Colors.green,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // Edit button
                  OutlinedButton.icon(
                    onPressed: () => _editOffer(offer),
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // Delete button
                  OutlinedButton.icon(
                    onPressed: () => _deleteOffer(offer['id']),
                    icon: const Icon(Icons.delete, size: 16),
                    label: const Text('Delete', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
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

// ============================================================
// Offer Form Dialog with Notification Toggle
// ============================================================

class OfferFormDialog extends StatefulWidget {
  final bool isEditing;
  final Map<String, dynamic>? offer;
  final bool sendNotificationToFollowers;
  final Function(bool) onNotificationToggle;
  
  const OfferFormDialog({
    super.key,
    required this.isEditing,
    this.offer,
    required this.sendNotificationToFollowers,
    required this.onNotificationToggle,
  });
  
  @override
  State<OfferFormDialog> createState() => _OfferFormDialogState();
}

class _OfferFormDialogState extends State<OfferFormDialog> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _discountValueController;
  late TextEditingController _pointsRequiredController;
  late TextEditingController _usageLimitController;
  
  String _discountType = 'percentage';
  DateTime _validFrom = DateTime.now();
  DateTime _validTo = DateTime.now().add(const Duration(days: 30));
  bool _sendNotification = true;
  
  @override
  void initState() {
    super.initState();
    _sendNotification = widget.sendNotificationToFollowers;
    
    if (widget.isEditing && widget.offer != null) {
      _titleController = TextEditingController(text: widget.offer!['title']);
      _descriptionController = TextEditingController(text: widget.offer!['description'] ?? '');
      _discountValueController = TextEditingController(
        text: widget.offer!['discount_value']?.toString() ?? '',
      );
      _pointsRequiredController = TextEditingController(
        text: widget.offer!['points_required']?.toString() ?? '0',
      );
      _usageLimitController = TextEditingController(
        text: widget.offer!['usage_limit']?.toString() ?? '',
      );
      _discountType = widget.offer!['discount_type'] ?? 'percentage';
      _validFrom = DateTime.parse(widget.offer!['valid_from']);
      _validTo = DateTime.parse(widget.offer!['valid_to']);
    } else {
      _titleController = TextEditingController();
      _descriptionController = TextEditingController();
      _discountValueController = TextEditingController();
      _pointsRequiredController = TextEditingController(text: '0');
      _usageLimitController = TextEditingController();
    }
  }
  
  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _discountValueController.dispose();
    _pointsRequiredController.dispose();
    _usageLimitController.dispose();
    super.dispose();
  }
  
  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: _validFrom,
        end: _validTo,
      ),
    );
    
    if (picked != null) {
      setState(() {
        _validFrom = picked.start;
        _validTo = picked.end;
      });
    }
  }
  
  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.pop(context, {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'discount_type': _discountType,
        'discount_value': double.parse(_discountValueController.text),
        'points_required': int.parse(_pointsRequiredController.text),
        'valid_from': _validFrom.toIso8601String().split('T')[0],
        'valid_to': _validTo.toIso8601String().split('T')[0],
        'image_url': null,
        'usage_limit': _usageLimitController.text.isNotEmpty 
            ? int.parse(_usageLimitController.text) 
            : null,
        'send_notification': _sendNotification,
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 650),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    widget.isEditing ? Icons.edit : Icons.add,
                    color: const Color(0xFFFF6B8B),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.isEditing ? 'Edit Offer' : 'Create New Offer',
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
            const SizedBox(height: 16),
            
            // Form
            Expanded(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      const Text(
                        'Offer Title *',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          hintText: 'e.g., Summer Special',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter offer title';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Description
                      const Text('Description'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'Describe your offer...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Discount Type
                      const Text('Discount Type *'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Percentage %'),
                              selected: _discountType == 'percentage',
                              onSelected: (selected) {
                                if (selected) setState(() => _discountType = 'percentage');
                              },
                              selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Fixed Rs.'),
                              selected: _discountType == 'fixed',
                              onSelected: (selected) {
                                if (selected) setState(() => _discountType = 'fixed');
                              },
                              selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Free Service'),
                              selected: _discountType == 'free_service',
                              onSelected: (selected) {
                                if (selected) setState(() => _discountType = 'free_service');
                              },
                              selectedColor: const Color(0xFFFF6B8B).withValues(alpha: 0.2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Discount Value
                      if (_discountType != 'free_service') ...[
                        const Text('Discount Value *'),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _discountValueController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: _discountType == 'percentage' ? 'e.g., 20' : 'e.g., 500',
                            prefixText: _discountType == 'percentage' ? '% ' : 'Rs. ',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter discount value';
                            }
                            if (double.tryParse(value) == null) {
                              return 'Please enter a valid number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Points Required
                      const Text('Points Required (0 for all customers)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _pointsRequiredController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: '0',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Usage Limit
                      const Text('Usage Limit (Optional)'),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _usageLimitController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Leave empty for unlimited',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Valid Period
                      const Text('Valid Period *'),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _selectDateRange,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, color: Color(0xFFFF6B8B)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${DateFormat('MMM dd, yyyy').format(_validFrom)} - ${DateFormat('MMM dd, yyyy').format(_validTo)}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // ✅ Send Notification to Followers - Toggle Switch
                      if (!widget.isEditing)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.notifications_active,
                                  color: Colors.blue,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Notify Followers',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      'Send push notification to all salon followers',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _sendNotification,
                                onChanged: (value) {
                                  setState(() {
                                    _sendNotification = value;
                                  });
                                  widget.onNotificationToggle(value);
                                },
                                activeThumbColor: const Color(0xFFFF6B8B),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B8B),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(widget.isEditing ? 'Update' : 'Create'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}