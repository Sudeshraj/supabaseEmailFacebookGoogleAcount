import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/timezone_service.dart';
import '../../theme/app_theme.dart';
import '../../extensions/context_extensions.dart';

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
  String _selectedFilter = 'all';
  String _selectedSort = 'newest';

  // ============================================
  // TIMEZONE VARIABLES
  // ============================================
  String _userTimezone = '';
  bool _isTimezoneLoaded = false;

  // ✅ Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeTimezone();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkForTimezoneChange();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ============================================
  // TIMEZONE INITIALIZATION
  // ============================================

  Future<void> _initializeTimezone() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();
    _userTimezone =
        prefs.getString('cached_timezone') ??
        TimezoneService.getCurrentTimezone();
    await TimezoneService.setTimezone(_userTimezone);

    if (mounted) {
      setState(() {
        _isTimezoneLoaded = true;
      });
    }

    debugPrint('✅ User timezone: $_userTimezone');

    await _loadOffers();
  }

  Future<void> _checkForTimezoneChange() async {
    final prefs = await SharedPreferences.getInstance();
    final currentTimezone =
        prefs.getString('cached_timezone') ??
        TimezoneService.getCurrentTimezone();

    if (_userTimezone != currentTimezone && _userTimezone.isNotEmpty) {
      _userTimezone = currentTimezone;
      await TimezoneService.setTimezone(_userTimezone);
      if (mounted) {
        await _loadOffers();
      }
    }
  }

  // ============================================
  // ✅ TIMEZONE HELPER METHODS
  // ============================================

  int _getDaysLeftLocal(String validToUtc) {
    try {
      final utcDate = DateTime.parse(validToUtc);
      final localDateTime = TimezoneService.utcToLocalDateTimeForDate(
        '00:00:00',
        utcDate,
      );
      final localDate = DateTime(
        localDateTime.year,
        localDateTime.month,
        localDateTime.day,
      );

      final now = DateTime.now();
      final todayLocal = DateTime(now.year, now.month, now.day);

      return localDate.difference(todayLocal).inDays;
    } catch (e) {
      debugPrint('Error calculating days left: $e');
      return -1;
    }
  }

  bool _isOfferActiveLocally(Map<String, dynamic> offer) {
    try {
      final validFromUtc = DateTime.parse(offer['valid_from']);
      final validToUtc = DateTime.parse(offer['valid_to']);

      final validFromLocal = TimezoneService.utcToLocalDateTimeForDate(
        '00:00:00',
        validFromUtc,
      );
      final validToLocal = TimezoneService.utcToLocalDateTimeForDate(
        '00:00:00',
        validToUtc,
      );

      final fromLocal = DateTime(
        validFromLocal.year,
        validFromLocal.month,
        validFromLocal.day,
      );
      final toLocal = DateTime(
        validToLocal.year,
        validToLocal.month,
        validToLocal.day,
      );

      final now = DateTime.now();
      final todayLocal = DateTime(now.year, now.month, now.day);

      return !fromLocal.isAfter(todayLocal) && toLocal.isAfter(todayLocal);
    } catch (e) {
      debugPrint('Error checking offer active: $e');
      return false;
    }
  }

  String _getTimezoneDisplay() {
    return TimezoneService.getFullTimezoneDisplay();
  }

  bool _isDST() {
    final timezone = _userTimezone;
    if (!timezone.contains('America/') && !timezone.contains('Europe/')) {
      return false;
    }
    final now = DateTime.now();
    final month = now.month;
    return month > 3 && month < 11;
  }

  // ============================================
  // LOAD OFFERS
  // ============================================

  Future<void> _loadOffers() async {
    if (!_isTimezoneLoaded) return;

    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });
    }

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Please login to view offers';
            _isLoading = false;
          });
        }
        return;
      }

      final customerCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', user.id)
          .eq('role_id', 3)
          .maybeSingle();

      if (customerCheck == null || customerCheck['status'] != 'active') {
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage =
                'Your account is not active. Please contact support.';
            _isLoading = false;
          });
        }
        return;
      }

      final profileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', user.id)
          .maybeSingle();

      if (profileCheck != null) {
        if (profileCheck['is_blocked'] == true) {
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage =
                  'Your account has been blocked. Please contact support.';
              _isLoading = false;
            });
          }
          return;
        }
        if (profileCheck['is_active'] == false) {
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage =
                  'Your profile is inactive. Please contact support.';
              _isLoading = false;
            });
          }
          return;
        }
      }

      final followedSalonsResult = await supabase
          .from('salon_followers')
          .select('salon_id')
          .eq('customer_id', user.id);

      if (followedSalonsResult.isEmpty) {
        if (mounted) {
          setState(() {
            _offers = [];
            _isLoading = false;
          });
        }
        return;
      }

      final List<int> followedSalonIds = [];
      for (var item in followedSalonsResult) {
        followedSalonIds.add(item['salon_id'] as int);
      }

      final todayUtc = DateTime.now().toUtc().toIso8601String().split('T')[0];

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
          .lte('valid_from', todayUtc)
          .gte('valid_to', todayUtc)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _offers = List<Map<String, dynamic>>.from(result);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading offers: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Failed to load offers. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  // ============================================
  // FILTERED AND SORTED OFFERS
  // ============================================

  List<Map<String, dynamic>> get _filteredAndSortedOffers {
    List<Map<String, dynamic>> filtered = List.from(_offers);

    switch (_selectedFilter) {
      case 'active':
        filtered = filtered
            .where((offer) => _isOfferActiveLocally(offer))
            .toList();
        break;
      case 'expiring':
        filtered = filtered.where((offer) {
          final daysLeft = _getDaysLeftLocal(offer['valid_to']);
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

    switch (_selectedSort) {
      case 'newest':
        filtered.sort((a, b) {
          final aDate = DateTime.parse(a['valid_from']);
          final bDate = DateTime.parse(b['valid_from']);
          return bDate.compareTo(aDate);
        });
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

  // ============================================
  // HELPER METHODS
  // ============================================

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
      case 'percentage':
        return '💰';
      case 'fixed':
        return '💵';
      case 'free_service':
        return '🎁';
      default:
        return '🏷️';
    }
  }

  Color _getDiscountColor(String? discountType) {
    switch (discountType) {
      case 'percentage':
        return AppTheme.primary;
      case 'fixed':
        return Colors.green.shade600;
      case 'free_service':
        return Colors.purple.shade600;
      default:
        return Colors.orange.shade600;
    }
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

  // ============================================
  // APPLY OFFER
  // ============================================

  Future<void> _applyOffer(Map<String, dynamic> offer) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) {
          _showSnackBar('Please login to apply offers', Colors.orange);
          context.push('/login');
        }
        return;
      }

      final customerCheck = await supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', user.id)
          .eq('role_id', 3)
          .maybeSingle();

      if (customerCheck == null || customerCheck['status'] != 'active') {
        if (mounted) {
          _showSnackBar(
            'Your account is not active. Please contact support.',
            Colors.red,
          );
        }
        return;
      }

      final profileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', user.id)
          .maybeSingle();

      if (profileCheck != null) {
        if (profileCheck['is_blocked'] == true) {
          if (mounted) {
            _showSnackBar(
              'Your account has been blocked. Please contact support.',
              Colors.red,
            );
          }
          return;
        }
        if (profileCheck['is_active'] == false) {
          if (mounted) {
            _showSnackBar(
              'Your profile is inactive. Please contact support.',
              Colors.red,
            );
          }
          return;
        }
      }

      if (!_isOfferActiveLocally(offer)) {
        if (mounted) {
          _showSnackBar('This offer has expired', Colors.red);
        }
        return;
      }

      final pointsRequired = offer['points_required'] ?? 0;
      if (pointsRequired > 0) {
        final loyaltyResult = await supabase
            .from('customer_loyalty')
            .select('current_points')
            .eq('customer_id', user.id)
            .maybeSingle();

        final userPoints = loyaltyResult?['current_points'] ?? 0;
        if (userPoints < pointsRequired) {
          if (mounted) {
            _showSnackBar(
              'You need $pointsRequired points to apply this offer',
              Colors.orange,
            );
          }
          return;
        }
      }

      final usageLimit = offer['usage_limit'];
      final usedCount = offer['used_count'] ?? 0;
      if (usageLimit != null && usedCount >= usageLimit) {
        if (mounted) {
          _showSnackBar('This offer has reached its usage limit', Colors.red);
        }
        return;
      }

      final existingOffer = await supabase
          .from('customer_offers')
          .select('id, status')
          .eq('customer_id', user.id)
          .eq('offer_id', offer['id'])
          .maybeSingle();

      if (existingOffer != null) {
        if (existingOffer['status'] == 'active') {
          if (mounted) {
            _showSnackBar('You have already applied this offer', Colors.orange);
          }
          return;
        } else if (existingOffer['status'] == 'used') {
          if (mounted) {
            _showSnackBar('You have already used this offer', Colors.red);
          }
          return;
        }
      }

      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => AlertDialog(
          backgroundColor: context.backgroundColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Text(
                _getDiscountIcon(offer['discount_type']),
                style: const TextStyle(fontSize: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  offer['title'],
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: context.textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                offer['description'] ?? '',
                style: TextStyle(color: context.secondaryTextColor),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _getDiscountColor(
                    offer['discount_type'],
                  ).withValues(alpha: 0.1),
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
              if (pointsRequired > 0) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Requires $pointsRequired loyalty points',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (mounted) {
                  Navigator.pop(dialogContext, false);
                }
              },
              child: Text(
                'Cancel',
                style: TextStyle(color: context.secondaryTextColor),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (mounted) {
                  Navigator.pop(dialogContext, true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Apply Offer'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      if (confirmed != true) return;

      await supabase.from('customer_offers').insert({
        'customer_id': user.id,
        'offer_id': offer['id'],
        'claimed_at': DateTime.now().toIso8601String(),
        'expires_at': offer['valid_to'],
        'status': 'active',
      });

      await supabase
          .from('offers')
          .update({'used_count': (usedCount + 1)})
          .eq('id', offer['id']);

      if (pointsRequired > 0) {
        final loyaltyResult = await supabase
            .from('customer_loyalty')
            .select('current_points')
            .eq('customer_id', user.id)
            .maybeSingle();

        final currentPoints = loyaltyResult?['current_points'] ?? 0;
        final newPoints = currentPoints - pointsRequired;

        await supabase
            .from('customer_loyalty')
            .update({
              'current_points': newPoints,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('customer_id', user.id);

        await supabase.from('loyalty_transactions').insert({
          'customer_id': user.id,
          'points': -pointsRequired,
          'type': 'redeem',
          'source': 'offer',
          'reference_id': offer['id'].toString(),
          'description':
              'Redeemed $pointsRequired points for ${offer['title']}',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (mounted) {
        _showSnackBar(
          '✅ "${offer['title']}" applied successfully!',
          Colors.green,
        );
      }

      if (mounted) {
        context.push('/customer/booking-flow', extra: {'offer': offer});
      }
    } catch (e) {
      debugPrint('Error applying offer: $e');
      if (mounted) {
        _showSnackBar('Error applying offer. Please try again.', Colors.red);
      }
    }
  }

  // ============================================
  // NAVIGATION METHODS
  // ============================================

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

  // ============================================
  // TIMEZONE INFO WIDGET - WITH DARK MODE
  // ============================================

  Widget _buildTimezoneInfoCard() {
    final isDark = context.isDarkMode;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.blue[900]!.withValues(alpha: 0.2)
            : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.blue[700]!.withValues(alpha: 0.3)
              : Colors.blue.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.access_time,
            size: 16,
            color: isDark ? Colors.blue[300] : Colors.blue,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '⏰ Offers shown in your local timezone: ${_getTimezoneDisplay()}',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.blue[300] : Colors.blueGrey,
              ),
            ),
          ),
          if (_isDST())
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.amber[800]!.withValues(alpha: 0.3)
                    : Colors.amber.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'DST',
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? Colors.amber[300] : Colors.amber.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================
  // OFFER CARD - WITH DARK MODE
  // ============================================

  Widget _buildOfferCard(Map<String, dynamic> offer, {required bool isMobile}) {
    final isDark = context.isDarkMode;
    final salonData = offer['salons'];
    final salonName = salonData != null ? salonData['name'] : 'Salon';
    final salonLogo = salonData != null ? salonData['logo_url'] : null;
    final salonAddress = salonData != null ? salonData['address'] : null;

    final daysLeft = _getDaysLeftLocal(offer['valid_to']);
    final discountColor = _getDiscountColor(offer['discount_type']);
    final discountIcon = _getDiscountIcon(offer['discount_type']);
    final discountText = _getDiscountText(offer);

    String statusText = '';
    Color? statusColor = Colors.green;

    if (daysLeft < 0) {
      statusText = 'Expired';
      statusColor = isDark ? Colors.red[300] : Colors.red;
    } else if (daysLeft == 0) {
      statusText = 'Last day';
      statusColor = isDark ? Colors.orange[300] : Colors.orange;
    } else if (daysLeft <= 3) {
      statusText = '$daysLeft days left';
      statusColor = isDark ? Colors.orange[300] : Colors.orange;
    } else if (daysLeft <= 7) {
      statusText = '$daysLeft days left';
      statusColor = isDark ? Colors.blue[300] : Colors.blue;
    } else {
      statusText = '$daysLeft days left';
      statusColor = isDark ? Colors.green[300] : Colors.green;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        onTap: () => _applyOffer(offer),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? discountColor.withValues(alpha: 0.15)
                    : discountColor.withValues(alpha: 0.05),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _navigateToSalonProfile(salonData),
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: isDark
                          ? discountColor.withValues(alpha: 0.2)
                          : discountColor.withValues(alpha: 0.1),
                      backgroundImage: salonLogo != null
                          ? NetworkImage(salonLogo)
                          : null,
                      child: salonLogo == null
                          ? Text(
                              salonName.isNotEmpty
                                  ? salonName[0].toUpperCase()
                                  : 'S',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : discountColor,
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
                              color: isDark ? Colors.white : Colors.grey[800],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (salonAddress != null)
                          Text(
                            salonAddress,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.grey[500],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  Container(
                    constraints: const BoxConstraints(minWidth: 70),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor?.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time, size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: statusColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          discountColor,
                          discountColor.withValues(alpha: 0.7),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          discountIcon,
                          style: const TextStyle(fontSize: 16),
                        ),
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

                  Text(
                    offer['title'],
                    style: TextStyle(
                      fontSize: isMobile ? 18 : 20,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),

                  Text(
                    offer['description'] ?? '',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.grey[600],
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),

                  if ((offer['points_required'] ?? 0) > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.amber[800]!.withValues(alpha: 0.2)
                            : Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${offer['points_required']} points required',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.amber[300]
                                  : Colors.amber.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),

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
                          foregroundColor: isDark
                              ? Colors.white60
                              : Colors.grey[600],
                          side: BorderSide(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[300]!,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'View Salon',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : Colors.grey[600],
                          ),
                        ),
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

  // ============================================
  // WEB LAYOUT
  // ============================================

  Widget _buildWebLayout() {
    final isDark = context.isDarkMode;
    final filteredOffers = _filteredAndSortedOffers;

    return Container(
      color: isDark ? const Color(0xFF121212) : Colors.grey[50],
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            children: [
              _buildTimezoneInfoCard(),
              _buildFilterSortBar(),
              const SizedBox(height: 16),
              Expanded(
                child: filteredOffers.isEmpty
                    ? _buildEmptyFilterWidget()
                    : GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 400,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.9,
                            ),
                        itemCount: filteredOffers.length,
                        itemBuilder: (context, index) => _buildOfferCard(
                          filteredOffers[index],
                          isMobile: false,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
  // MOBILE LAYOUT
  // ============================================

  Widget _buildMobileLayout() {
    final filteredOffers = _filteredAndSortedOffers;

    return Column(
      children: [
        _buildTimezoneInfoCard(),
        _buildFilterSortBar(),
        const SizedBox(height: 16),
        Expanded(
          child: filteredOffers.isEmpty
              ? _buildEmptyFilterWidget()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredOffers.length,
                  itemBuilder: (context, index) =>
                      _buildOfferCard(filteredOffers[index], isMobile: true),
                ),
        ),
      ],
    );
  }

  // ============================================
  // FILTER AND SORT BAR - WITH DARK MODE
  // ============================================

  Widget _buildFilterSortBar() {
    final isDark = context.isDarkMode;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
                borderRadius: BorderRadius.circular(25),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedFilter,
                  icon: Icon(
                    Icons.filter_list,
                    size: 18,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                  isExpanded: true,
                  dropdownColor: isDark
                      ? const Color(0xFF2A2A2A)
                      : Colors.white,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All Offers')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(
                      value: 'expiring',
                      child: Text('Expiring Soon'),
                    ),
                    DropdownMenuItem(
                      value: 'points',
                      child: Text('Points Required'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedFilter = value);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
                borderRadius: BorderRadius.circular(25),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedSort,
                  icon: Icon(
                    Icons.sort,
                    size: 18,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                  ),
                  isExpanded: true,
                  dropdownColor: isDark
                      ? const Color(0xFF2A2A2A)
                      : Colors.white,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text('Newest First'),
                    ),
                    DropdownMenuItem(
                      value: 'discount',
                      child: Text('Best Discount'),
                    ),
                    DropdownMenuItem(
                      value: 'points',
                      child: Text('Lowest Points'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedSort = value);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${_filteredAndSortedOffers.length}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.primary,
            ),
          ),
          Text(
            ' offers',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // EMPTY FILTER WIDGET - WITH DARK MODE
  // ============================================

  Widget _buildEmptyFilterWidget() {
    final isDark = context.isDarkMode;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.filter_alt_off,
            size: 48,
            color: isDark ? Colors.white30 : Colors.grey[400],
          ),
          const SizedBox(height: 12),
          Text(
            'No offers match your filter',
            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedFilter = 'all';
                _selectedSort = 'newest';
              });
            },
            child: Text(
              'Clear Filters',
              style: TextStyle(color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // ✅ MAIN BUILD METHOD - WITH EDGE-TO-EDGE
  // ============================================

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWeb = screenWidth > 800;
    final isDark = context.isDarkMode;

    if (!_isTimezoneLoaded) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[50],
        appBar: AppBar(
          title: const Text(
            'Special Offers',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Back',
          ),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppTheme.primary),
              SizedBox(height: 16),
              Text('Loading timezone...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Special Offers',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadOffers,
            tooltip: 'Refresh',
          ),
        ],
      ),
      // ✅ EDGE-TO-EDGE: SafeArea with Web/Mobile Layout
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Loading offers...',
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              )
            : _hasError
            ? _buildErrorWidget()
            : _offers.isEmpty
            ? _buildEmptyOffersWidget()
            : isWeb
            ? _buildWebLayout()
            : _buildMobileLayout(),
      ),
    );
  }

  // ============================================
  // ERROR WIDGET - WITH DARK MODE
  // ============================================

  Widget _buildErrorWidget() {
    final isDark = context.isDarkMode;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: isDark ? Colors.white70 : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            style: TextStyle(color: isDark ? Colors.white60 : Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadOffers,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  // ============================================
  // EMPTY OFFERS WIDGET - WITH DARK MODE
  // ============================================

  Widget _buildEmptyOffersWidget() {
    final isDark = context.isDarkMode;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark
                  ? AppTheme.primary.withValues(alpha: 0.1)
                  : AppTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.local_offer_outlined,
              size: 64,
              color: isDark
                  ? AppTheme.primary.withValues(alpha: 0.5)
                  : AppTheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Offers Available',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Follow salons to see their special offers here',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white60 : Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Browse Salons'),
          ),
        ],
      ),
    );
  }
}
