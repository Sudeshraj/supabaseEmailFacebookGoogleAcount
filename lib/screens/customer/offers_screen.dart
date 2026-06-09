import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  final supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _offers = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  
  // Filter and sort state
  String _selectedFilter = 'all'; // all, active, expiring, points
  String _selectedSort = 'newest'; // newest, discount, points
  
  @override
  void initState() {
    super.initState();
    _loadOffers();
  }
  
  Future<void> _loadOffers() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Please login to view offers';
          _isLoading = false;
        });
        return;
      }
      
      // Get followed salon IDs
      final followedSalonsResult = await supabase
          .from('salon_followers')
          .select('salon_id')
          .eq('customer_id', user.id);
      
      if (followedSalonsResult.isEmpty) {
        setState(() {
          _offers = [];
          _isLoading = false;
        });
        return;
      }
      
      final List<int> followedSalonIds = [];
      for (var item in followedSalonsResult) {
        followedSalonIds.add(item['salon_id'] as int);
      }
      
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      // Load offers from followed salons
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
            salon_id,
            salons:salon_id (
              id,
              name,
              logo_url,
              address,
              phone
            )
          ''')
          .inFilter('salon_id', followedSalonIds)
          .eq('is_active', true)
          .lte('valid_from', today)
          .gte('valid_to', today)
          .order('created_at', ascending: false);
      
      if (result.isNotEmpty) {
        setState(() {
          _offers = List<Map<String, dynamic>>.from(result);
          _isLoading = false;
        });
      } else {
        setState(() {
          _offers = [];
          _isLoading = false;
        });
      }
      
    } catch (e) {
      debugPrint('Error loading offers: $e');
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to load offers. Please try again.';
        _isLoading = false;
      });
    }
  }
  
  List<Map<String, dynamic>> get _filteredAndSortedOffers {
    List<Map<String, dynamic>> filtered = List.from(_offers);
    
    // Apply filter
    switch (_selectedFilter) {
      case 'active':
        filtered = filtered.where((offer) {
          final validTo = DateTime.parse(offer['valid_to']);
          return validTo.isAfter(DateTime.now());
        }).toList();
        break;
      case 'expiring':
        filtered = filtered.where((offer) {
          final validTo = DateTime.parse(offer['valid_to']);
          final daysLeft = validTo.difference(DateTime.now()).inDays;
          return daysLeft <= 7 && daysLeft >= 0;
        }).toList();
        break;
      case 'points':
        filtered = filtered.where((offer) {
          return (offer['points_required'] ?? 0) > 0;
        }).toList();
        break;
      default:
        break;
    }
    
    // Apply sort
    switch (_selectedSort) {
      case 'newest':
        filtered.sort((a, b) => DateTime.parse(b['valid_from']).compareTo(DateTime.parse(a['valid_from'])));
        break;
      case 'discount':
        filtered.sort((a, b) {
          final aValue = (a['discount_value'] ?? 0).toDouble();
          final bValue = (b['discount_value'] ?? 0).toDouble();
          return bValue.compareTo(aValue);
        });
        break;
      case 'points':
        filtered.sort((a, b) {
          final aPoints = a['points_required'] ?? 0;
          final bPoints = b['points_required'] ?? 0;
          return aPoints.compareTo(bPoints);
        });
        break;
      default:
        break;
    }
    
    return filtered;
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
  
  String _getDiscountIcon(String? discountType) {
    switch (discountType) {
      case 'percentage': return '💰';
      case 'fixed': return '💵';
      case 'free_service': return '🎁';
      default: return '🏷️';
    }
  }
  
  Color _getDiscountColor(String? discountType) {
    switch (discountType) {
      case 'percentage': return const Color(0xFFFF6B8B);
      case 'fixed': return Colors.green.shade600;
      case 'free_service': return Colors.purple.shade600;
      default: return Colors.orange.shade600;
    }
  }
  
  int _getDaysLeft(String validTo) {
    final date = DateTime.parse(validTo);
    return date.difference(DateTime.now()).inDays;
  }
  
  void _applyOffer(Map<String, dynamic> offer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Text(_getDiscountIcon(offer['discount_type']), style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                offer['title'],
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(offer['description'] ?? ''),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getDiscountColor(offer['discount_type']).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  _getDiscountText(offer),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _getDiscountColor(offer['discount_type']),
                  ),
                ),
              ),
            ),
            if ((offer['points_required'] ?? 0) > 0) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Requires ${offer['points_required']} loyalty points',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showSnackBar('✅ "${offer['title']}" applied!');
              context.push('/customer/booking-flow', extra: {'offer': offer});
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Apply Offer'),
          ),
        ],
      ),
    );
  }
  
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  void _navigateToSalonProfile(Map<String, dynamic> salonData) {
    final salon = {
      'id': salonData['id'],
      'name': salonData['name'],
      'logo_url': salonData['logo_url'],
      'address': salonData['address'],
      'phone': salonData['phone'],
    };
    context.push('/customer/salon-profile', extra: salon);
  }
  
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1200;
    final isDesktop = screenWidth >= 1200;
    
    // Responsive grid settings
    int crossAxisCount = 1;
    double cardWidth = double.infinity;
    
    if (isDesktop) {
      crossAxisCount = 2;
      cardWidth = 500;
    } else if (isTablet) {
      crossAxisCount = 2;
      cardWidth = 350;
    } else {
      crossAxisCount = 1;
      cardWidth = double.infinity;
    }
    
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Special Offers',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadOffers,
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
                        onPressed: _loadOffers,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B8B),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Try Again'),
                      ),
                    ],
                  ),
                )
              : _offers.isEmpty
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
                            'No Offers Available',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Follow salons to see their special offers here',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6B8B),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Browse Salons'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Filter and Sort Bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // Filter dropdown
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedFilter,
                                    icon: const Icon(Icons.filter_list, size: 18),
                                    items: const [
                                      DropdownMenuItem(value: 'all', child: Text('All Offers')),
                                      DropdownMenuItem(value: 'active', child: Text('Active')),
                                      DropdownMenuItem(value: 'expiring', child: Text('Expiring Soon')),
                                      DropdownMenuItem(value: 'points', child: Text('Points Required')),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() => _selectedFilter = value);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Sort dropdown
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(25),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedSort,
                                    icon: const Icon(Icons.sort, size: 18),
                                    items: const [
                                      DropdownMenuItem(value: 'newest', child: Text('Newest First')),
                                      DropdownMenuItem(value: 'discount', child: Text('Best Discount')),
                                      DropdownMenuItem(value: 'points', child: Text('Lowest Points')),
                                    ],
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() => _selectedSort = value);
                                      }
                                    },
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_filteredAndSortedOffers.length} offers',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Offers Grid/List
                        Expanded(
                          child: _filteredAndSortedOffers.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.filter_alt_off, size: 48, color: Colors.grey[400]),
                                      const SizedBox(height: 12),
                                      Text(
                                        'No offers match your filter',
                                        style: TextStyle(color: Colors.grey[500]),
                                      ),
                                    ],
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: isDesktop || isTablet
                                      ? GridView.builder(
                                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: crossAxisCount,
                                            crossAxisSpacing: 16,
                                            mainAxisSpacing: 16,
                                            childAspectRatio: isDesktop ? 1.1 : 1.0,
                                          ),
                                          itemCount: _filteredAndSortedOffers.length,
                                          itemBuilder: (context, index) => _buildOfferCard(
                                            _filteredAndSortedOffers[index],
                                            isMobile: isMobile,
                                          ),
                                        )
                                      : ListView.builder(
                                          itemCount: _filteredAndSortedOffers.length,
                                          itemBuilder: (context, index) => _buildOfferCard(
                                            _filteredAndSortedOffers[index],
                                            isMobile: isMobile,
                                          ),
                                        ),
                                ),
                        ),
                      ],
                    ),
    );
  }
  
  Widget _buildOfferCard(Map<String, dynamic> offer, {required bool isMobile}) {
    final salonData = offer['salons'];
    final salonName = salonData != null ? salonData['name'] : 'Salon';
    final salonLogo = salonData != null ? salonData['logo_url'] : null;
    final salonAddress = salonData != null ? salonData['address'] : null;
    
    final validTo = DateTime.parse(offer['valid_to']);
    final daysLeft = _getDaysLeft(offer['valid_to']);
    final discountColor = _getDiscountColor(offer['discount_type']);
    final discountIcon = _getDiscountIcon(offer['discount_type']);
    final discountText = _getDiscountText(offer);
    
    String statusText = '';
    Color statusColor = Colors.green;
    
    if (daysLeft < 0) {
      statusText = 'Expired';
      statusColor = Colors.red;
    } else if (daysLeft <= 3) {
      statusText = '$daysLeft days left';
      statusColor = Colors.orange;
    } else if (daysLeft <= 7) {
      statusText = '$daysLeft days left';
      statusColor = Colors.blue;
    } else {
      statusText = '$daysLeft days left';
      statusColor = Colors.green;
    }
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () => _applyOffer(offer),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with Salon Info
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: discountColor.withValues(alpha: 0.05),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  // Salon Logo
                  GestureDetector(
                    onTap: () => _navigateToSalonProfile(salonData),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: discountColor.withValues(alpha: 0.1),
                      backgroundImage: salonLogo != null ? NetworkImage(salonLogo) : null,
                      child: salonLogo == null
                          ? Text(
                              salonName.isNotEmpty ? salonName[0].toUpperCase() : 'S',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: discountColor,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => _navigateToSalonProfile(salonData),
                          child: Text(
                            salonName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),
                        if (salonAddress != null)
                          Text(
                            salonAddress,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  // Days left badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Offer Content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Discount Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [discountColor, discountColor.withValues(alpha: 0.7)],
                      ),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(discountIcon, style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 8),
                        Text(
                          discountText,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Title
                  Text(
                    offer['title'],
                    style: TextStyle(
                      fontSize: isMobile ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
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
                  const SizedBox(height: 16),
                  
                  // Points Required (if any)
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
                            '${offer['points_required']} points required',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _applyOffer(offer),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: discountColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Apply Offer',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => _navigateToSalonProfile(salonData),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                          side: BorderSide(color: Colors.grey[300]!),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('View Salon'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}