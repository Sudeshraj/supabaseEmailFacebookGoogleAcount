import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../extensions/context_extensions.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  // Data
  Map<String, dynamic>? _loyalty;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _badges = [];
  List<Map<String, dynamic>> _earnedBadges = [];

  // Tab
  late TabController _tabController;

  // ✅ API 36: Responsive variables
  bool _isTablet = false;
  bool _isWeb = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadLoyaltyData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScreenSize();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkScreenSize();
  }

  void _checkScreenSize() {
    final size = MediaQuery.of(context).size;
    final isTablet = size.shortestSide >= 600;
    final isWeb = size.width > 800;

    if (_isTablet != isTablet || _isWeb != isWeb) {
      setState(() {
        _isTablet = isTablet;
        _isWeb = isWeb;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ============================================
  // TIER HELPERS
  // ============================================

  int get _currentPoints =>
      (_loyalty?['current_points'] as num?)?.toInt() ?? 0;
  int get _lifetimePoints =>
      (_loyalty?['lifetime_points'] as num?)?.toInt() ?? 0;
  String get _tier => _loyalty?['tier']?.toString() ?? 'Bronze';

  Color _tierColor(String tier) {
    switch (tier) {
      case 'Platinum':
        return AppTheme.platinum;
      case 'Gold':
        return AppTheme.gold;
      case 'Silver':
        return AppTheme.silver;
      case 'Bronze':
      default:
        return AppTheme.bronze;
    }
  }

  IconData _tierIcon(String tier) {
    switch (tier) {
      case 'Platinum':
        return Icons.workspace_premium;
      case 'Gold':
        return Icons.military_tech;
      case 'Silver':
        return Icons.verified;
      case 'Bronze':
      default:
        return Icons.star;
    }
  }

  // ✅ Tier Emoji
  String _tierEmoji(String tier) {
    switch (tier) {
      case 'Platinum':
        return '💎';
      case 'Gold':
        return '🥇';
      case 'Silver':
        return '🥈';
      case 'Bronze':
      default:
        return '🥉';
    }
  }

  // ✅ Tier Description - User ට තේරෙන විදියට
  String _tierDescription(String tier) {
    switch (tier) {
      case 'Platinum':
        return 'Premium tier with exclusive VIP benefits';
      case 'Gold':
        return 'Priority booking and special discounts';
      case 'Silver':
        return 'Faster service and bonus points';
      case 'Bronze':
      default:
        return 'Start your loyalty journey - earn points and unlock rewards!';
    }
  }

  // ✅ Tier Benefits - User ට තේරෙන විදියට
  List<Map<String, dynamic>> _tierBenefits(String tier) {
    switch (tier) {
      case 'Platinum':
        return [
          {'icon': Icons.flash_on, 'text': 'Instant priority booking', 'color': AppTheme.platinum},
          {'icon': Icons.percent, 'text': '20% off all services', 'color': AppTheme.success},
          {'icon': Icons.card_giftcard, 'text': 'Free monthly premium service', 'color': AppTheme.warning},
          {'icon': Icons.people, 'text': 'Exclusive VIP customer support', 'color': Colors.blue},
          {'icon': Icons.event, 'text': 'Early access to new services', 'color': Colors.purple},
        ];
      case 'Gold':
        return [
          {'icon': Icons.flash_on, 'text': 'Priority booking', 'color': AppTheme.gold},
          {'icon': Icons.percent, 'text': '15% off all services', 'color': AppTheme.success},
          {'icon': Icons.card_giftcard, 'text': 'Monthly bonus points', 'color': AppTheme.warning},
          {'icon': Icons.people, 'text': 'Dedicated customer support', 'color': Colors.blue},
        ];
      case 'Silver':
        return [
          {'icon': Icons.flash_on, 'text': 'Faster booking queue', 'color': AppTheme.silver},
          {'icon': Icons.percent, 'text': '10% off all services', 'color': AppTheme.success},
          {'icon': Icons.card_giftcard, 'text': 'Bonus points on reviews', 'color': AppTheme.warning},
        ];
      case 'Bronze':
      default:
        return [
          {'icon': Icons.stars, 'text': 'Earn points on every booking', 'color': AppTheme.bronze},
          {'icon': Icons.card_giftcard, 'text': 'Redeem points for discounts', 'color': AppTheme.success},
          {'icon': Icons.emoji_events, 'text': 'Unlock badges as you earn', 'color': AppTheme.warning},
        ];
    }
  }

  // ✅ All Tiers for Progress Tracker
  List<Map<String, dynamic>> get _allTiers => [
    {
      'name': 'Bronze',
      'emoji': '🥉',
      'color': AppTheme.bronze,
      'minPoints': 0,
      'maxPoints': 200,
      'icon': Icons.star,
    },
    {
      'name': 'Silver',
      'emoji': '🥈',
      'color': AppTheme.silver,
      'minPoints': 200,
      'maxPoints': 500,
      'icon': Icons.verified,
    },
    {
      'name': 'Gold',
      'emoji': '🥇',
      'color': AppTheme.gold,
      'minPoints': 500,
      'maxPoints': 1000,
      'icon': Icons.military_tech,
    },
    {
      'name': 'Platinum',
      'emoji': '💎',
      'color': AppTheme.platinum,
      'minPoints': 1000,
      'maxPoints': 999999,
      'icon': Icons.workspace_premium,
    },
  ];

  double get _tierProgress {
    const tierThresholds = {
      'Bronze': [0, 200],
      'Silver': [200, 500],
      'Gold': [500, 1000],
      'Platinum': [1000, 1000],
    };

    final range = tierThresholds[_tier] ?? [0, 1000];
    final min = range[0];
    final max = range[1];

    if (_tier == 'Platinum' || max <= min) return 1.0;

    final progress = (_lifetimePoints - min) / (max - min);
    return progress.clamp(0.0, 1.0);
  }

  int get _nextTierMinPoints {
    switch (_tier) {
      case 'Bronze':
        return 200;
      case 'Silver':
        return 500;
      case 'Gold':
        return 1000;
      case 'Platinum':
      default:
        return 1000;
    }
  }

  String get _nextTierName {
    switch (_tier) {
      case 'Bronze':
        return 'Silver';
      case 'Silver':
        return 'Gold';
      case 'Gold':
        return 'Platinum';
      case 'Platinum':
      default:
        return 'Max';
    }
  }

  // ============================================
  // LOAD DATA
  // ============================================

  Future<void> _loadLoyaltyData() async {
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
            _errorMessage = 'Please login to view your loyalty program';
            _isLoading = false;
          });
        }
        return;
      }

      var loyalty = await supabase
          .from('customer_loyalty')
          .select()
          .eq('customer_id', user.id)
          .maybeSingle();

      if (loyalty == null) {
        try {
          await supabase.from('customer_loyalty').insert({
            'customer_id': user.id,
            'total_points': 0,
            'current_points': 0,
            'lifetime_points': 0,
            'tier': 'Bronze',
            'points_to_next_tier': 500,
          });

          loyalty = await supabase
              .from('customer_loyalty')
              .select()
              .eq('customer_id', user.id)
              .maybeSingle();
        } catch (e) {
          debugPrint('Error creating loyalty row: $e');
        }
      }

      final transactions = await supabase
          .from('loyalty_transactions')
          .select()
          .eq('customer_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);

      final allBadges = await supabase
          .from('badges')
          .select()
          .eq('is_active', true)
          .order('points_required', ascending: true);

      final earnedBadges = await supabase
          .from('customer_badges')
          .select('badge_id, earned_at')
          .eq('customer_id', user.id);

      if (!mounted) return;

      setState(() {
        _loyalty = loyalty;
        _transactions = List<Map<String, dynamic>>.from(transactions);
        _badges = List<Map<String, dynamic>>.from(allBadges);
        _earnedBadges = List<Map<String, dynamic>>.from(earnedBadges);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading loyalty data: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Failed to load loyalty data. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  // ============================================
  // TRANSACTION HELPERS
  // ============================================

  IconData _txIcon(String type, String source) {
    switch (source) {
      case 'booking':
        return Icons.event_available;
      case 'review':
        return Icons.rate_review;
      case 'referral':
        return Icons.people;
      case 'birthday':
        return Icons.cake;
      case 'promotion':
        return Icons.local_offer;
      case 'cancellation':
        return Icons.cancel;
      default:
        return Icons.stars;
    }
  }

  Color _txColor(String type) {
    switch (type) {
      case 'earn':
        return AppTheme.success;
      case 'redeem':
        return AppTheme.warning;
      case 'bonus':
        return Colors.purple;
      case 'expire':
        return AppTheme.error;
      default:
        return Colors.grey;
    }
  }

  String _txLabel(String type) {
    switch (type) {
      case 'earn':
        return 'Earned';
      case 'redeem':
        return 'Redeemed';
      case 'bonus':
        return 'Bonus';
      case 'expire':
        return 'Expired';
      default:
        return 'Transaction';
    }
  }

  String _sourceLabel(String source) {
    switch (source) {
      case 'booking':
        return 'Booking';
      case 'review':
        return 'Review';
      case 'referral':
        return 'Referral';
      case 'birthday':
        return 'Birthday';
      case 'promotion':
        return 'Promotion';
      case 'cancellation':
        return 'Cancellation';
      default:
        return source;
    }
  }

  bool _isBadgeEarned(int badgeId) {
    return _earnedBadges.any((b) => b['badge_id'] == badgeId);
  }

  DateTime? _getBadgeEarnedDate(int badgeId) {
    try {
      final entry = _earnedBadges.firstWhere((b) => b['badge_id'] == badgeId);
      return DateTime.parse(entry['earned_at']);
    } catch (e) {
      return null;
    }
  }

  // ============================================
  // BUILD
  // ============================================

  @override
  Widget build(BuildContext context) {
    final primaryColor = context.primaryColor;
    final backgroundColor = context.backgroundColor;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Loyalty Program',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        bottom: _isLoading || _hasError
            ? null
            : TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                ),
                tabs: const [
                  Tab(text: 'Overview'),
                  Tab(text: 'My Tier'),
                  Tab(text: 'History'),
                  Tab(text: 'Badges'),
                ],
              ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: _isWeb ? 1000 : double.infinity,
            ),
            child: _isLoading
                ? _buildLoadingState()
                : _hasError
                    ? _buildErrorState()
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildOverviewTab(),
                          _buildTierDetailsTab(),
                          _buildHistoryTab(),
                          _buildBadgesTab(),
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  // ============================================
  // LOADING / ERROR
  // ============================================

  Widget _buildLoadingState() {
    final primaryColor = context.primaryColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: primaryColor),
          const SizedBox(height: 16),
          Text(
            'Loading loyalty data...',
            style: context.bodyMedium.copyWith(color: secondaryTextColor),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
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
              style: context.bodyMedium.copyWith(color: secondaryTextColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadLoyaltyData,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // TAB 1: OVERVIEW
  // ============================================

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadLoyaltyData,
      color: context.primaryColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(_isWeb ? 24 : 16),
        child: _isTablet
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        _buildTierCard(),
                        const SizedBox(height: 16),
                        _buildPointsSummary(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildEarningGuide(),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTierCard(),
                  const SizedBox(height: 16),
                  _buildPointsSummary(),
                  const SizedBox(height: 16),
                  _buildEarningGuide(),
                ],
              ),
      ),
    );
  }

  // ============================================
  // TAB 2: MY TIER (NEW - Detailed Tier Info)
  // ============================================

  Widget _buildTierDetailsTab() {
    return RefreshIndicator(
      onRefresh: _loadLoyaltyData,
      color: context.primaryColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(_isWeb ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current Tier Explanation
            _buildCurrentTierExplanation(),
            const SizedBox(height: 20),

            // Your Benefits
            _buildYourBenefits(),
            const SizedBox(height: 20),

            // All Tiers Progress Tracker
            _buildTiersProgressTracker(),
            const SizedBox(height: 20),

            // How to Level Up
            _buildHowToLevelUp(),
          ],
        ),
      ),
    );
  }

  // Current Tier Explanation
  Widget _buildCurrentTierExplanation() {
    final isDark = context.isDarkMode;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final tierColor = _tierColor(_tier);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tierColor.withValues(alpha: isDark ? 0.25 : 0.15),
            tierColor.withValues(alpha: isDark ? 0.08 : 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tierColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _tierEmoji(_tier),
                style: const TextStyle(fontSize: 48),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'You are $_tier Member'.replaceAll('\$ ', ''),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: tierColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _tierDescription(_tier),
                      style: context.bodyMedium.copyWith(
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: tierColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _tier == 'Platinum'
                        ? 'You have reached the highest tier! Enjoy exclusive VIP benefits.'
                        : 'Earn $_nextTierMinPoints lifetime points to reach $_nextTierName tier and unlock more benefits.',
                    style: context.bodySmall.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Your Benefits
  Widget _buildYourBenefits() {
    final isDark = context.isDarkMode;
    final cardColor = context.cardColor;
    final textColor = context.textColor;
    final benefits = _tierBenefits(_tier);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.card_giftcard,
                color: AppTheme.success,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Your $_tier Benefits',
                style: context.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...benefits.map((benefit) => _buildBenefitRow(benefit, isDark)),
        ],
      ),
    );
  }

  Widget _buildBenefitRow(Map<String, dynamic> benefit, bool isDark) {
    final textColor = context.textColor;
    final color = benefit['color'] as Color;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              benefit['icon'] as IconData,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              benefit['text'] as String,
              style: context.bodyMedium.copyWith(
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(
            Icons.check_circle,
            size: 18,
            color: AppTheme.success,
          ),
        ],
      ),
    );
  }

  // Tiers Progress Tracker
  Widget _buildTiersProgressTracker() {
    final isDark = context.isDarkMode;
    final cardColor = context.cardColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.trending_up,
                color: Colors.blue,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Tier Progress',
                style: context.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Here\'s how the tier system works:',
            style: context.bodySmall.copyWith(color: secondaryTextColor),
          ),
          const SizedBox(height: 20),
          ..._allTiers.asMap().entries.map((entry) {
            final index = entry.key;
            final tier = entry.value;
            final isCurrent = tier['name'] == _tier;
            final isUnlocked =
                _lifetimePoints >= (tier['minPoints'] as int);
            final tierColor = tier['color'] as Color;

            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? tierColor.withValues(alpha: 0.1)
                        : isUnlocked
                            ? AppTheme.success.withValues(alpha: 0.05)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCurrent
                          ? tierColor.withValues(alpha: 0.4)
                          : isUnlocked
                              ? AppTheme.success.withValues(alpha: 0.2)
                              : (isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[200]!),
                      width: isCurrent ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Tier Emoji
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: tierColor.withValues(
                            alpha: isUnlocked ? 0.15 : 0.05,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            tier['emoji'] as String,
                            style: TextStyle(
                              fontSize: isUnlocked ? 24 : 20,
                              color: isUnlocked ? null : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Tier Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  tier['name'] as String,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isUnlocked
                                        ? textColor
                                        : (isDark
                                            ? Colors.white38
                                            : Colors.grey[400]),
                                  ),
                                ),
                                if (isCurrent) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tierColor,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Text(
                                      'YOU ARE HERE',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${tier['minPoints']}-${tier['maxPoints']} points',
                              style: context.bodySmall.copyWith(
                                color: isUnlocked
                                    ? secondaryTextColor
                                    : (isDark
                                        ? Colors.white30
                                        : Colors.grey[400]),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Status Icon
                      Icon(
                        isUnlocked
                            ? Icons.check_circle
                            : Icons.lock_outline,
                        color: isUnlocked
                            ? AppTheme.success
                            : (isDark ? Colors.white38 : Colors.grey[400]),
                        size: 24,
                      ),
                    ],
                  ),
                ),
                if (index < _allTiers.length - 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: isDark ? Colors.white30 : Colors.grey[400],
                      size: 20,
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  // How to Level Up
  Widget _buildHowToLevelUp() {
    final isDark = context.isDarkMode;
    final cardColor = context.cardColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    if (_tier == 'Platinum') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.platinum.withValues(alpha: 0.15),
              AppTheme.platinum.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.platinum.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          children: [
            const Text(
              '🎉',
              style: TextStyle(fontSize: 48),
            ),
            const SizedBox(height: 12),
            Text(
              'You\'ve Reached the Top!',
              style: context.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: AppTheme.platinum,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Congratulations! You\'re a Platinum member with all premium benefits unlocked. Keep earning points to enjoy exclusive rewards!',
              style: context.bodySmall.copyWith(color: secondaryTextColor),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.rocket_launch,
                color: AppTheme.warning,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'How to Level Up',
                style: context.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'You need ${_nextTierMinPoints - _lifetimePoints} more points to reach $_nextTierName!',
            style: context.bodyMedium.copyWith(
              color: _tierColor(_nextTierName),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          _buildHowToRow(
            Icons.event_available,
            'Book Appointments',
            'Earn 1 point for every Rs. 10 spent',
            AppTheme.success,
          ),
          const SizedBox(height: 12),
          _buildHowToRow(
            Icons.rate_review,
            'Write Reviews',
            'Get 10 bonus points for each review',
            Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildHowToRow(
            Icons.people,
            'Refer Friends',
            'Earn bonus points when friends book',
            Colors.purple,
          ),
          const SizedBox(height: 12),
          _buildHowToRow(
            Icons.cake,
            'Birthday Bonus',
            'Get special points on your birthday',
            Colors.pink,
          ),
        ],
      ),
    );
  }

  Widget _buildHowToRow(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              Text(
                subtitle,
                style: context.bodySmall.copyWith(color: secondaryTextColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================
  // TIER CARD (Overview Tab)
  // ============================================

  Widget _buildTierCard() {
    final tierColor = _tierColor(_tier);
    final isDark = context.isDarkMode;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tierColor.withValues(alpha: isDark ? 0.3 : 0.15),
            tierColor.withValues(alpha: isDark ? 0.1 : 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tierColor.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: tierColor.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _tierEmoji(_tier),
                  style: const TextStyle(fontSize: 32),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_tier Member',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: tierColor,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _tier == 'Platinum'
                          ? 'You\'ve reached the highest tier! 🎉'
                          : 'Progress to $_nextTierName',
                      style: context.bodyMedium.copyWith(color: secondaryTextColor),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          if (_tier != 'Platinum') ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$_lifetimePoints pts',
                  style: context.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                Text(
                  '$_nextTierMinPoints pts',
                  style: context.bodyMedium.copyWith(color: secondaryTextColor),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: _tierProgress,
                minHeight: 10,
                backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(tierColor),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${_nextTierMinPoints - _lifetimePoints} more points to $_nextTierName',
                style: context.bodySmall.copyWith(
                  fontStyle: FontStyle.italic,
                  color: secondaryTextColor,
                ),
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tierColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.emoji_events, color: tierColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You are a Platinum member — enjoy all premium benefits!',
                      style: context.bodySmall.copyWith(
                        fontWeight: FontWeight.w500,
                        color: textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Summary grid
  Widget _buildPointsSummary() {
    final isDark = context.isDarkMode;
    final cardColor = context.cardColor;
    final textColor = context.textColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: Colors.blue,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Points Summary',
                style: context.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Your points breakdown',
            style: context.bodySmall.copyWith(
              color: context.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildPointStat(
                  'Available',
                  _currentPoints,
                  Icons.savings,
                  AppTheme.success,
                  subtitle: 'Ready to redeem',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPointStat(
                  'Lifetime',
                  _lifetimePoints,
                  Icons.history,
                  Colors.purple,
                  subtitle: 'Total earned',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildPointStat(
                  'Current Tier',
                  null,
                  _tierIcon(_tier),
                  _tierColor(_tier),
                  textValue: '$_tier ${_tierEmoji(_tier)}',
                  subtitle: 'Your level',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPointStat(
                  'Next Tier',
                  _tier == 'Platinum' ? 0 : _nextTierMinPoints - _lifetimePoints,
                  Icons.trending_up,
                  Colors.orange,
                  suffix: _tier == 'Platinum' ? 'Max reached' : 'pts to go',
                  subtitle: _tier == 'Platinum' ? 'Highest tier' : 'to $_nextTierName',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPointStat(
    String label,
    int? value,
    IconData icon,
    Color color, {
    String? textValue,
    String? suffix,
    String? subtitle,
  }) {
    final secondaryTextColor = context.secondaryTextColor;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: context.bodySmall.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: secondaryTextColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                textValue ?? (value ?? 0).toString(),
                style: TextStyle(
                  fontSize: textValue != null ? 14 : 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              if (suffix != null && textValue == null) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    suffix,
                    style: context.bodySmall.copyWith(
                      fontSize: 10,
                      color: secondaryTextColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: context.bodySmall.copyWith(
                fontSize: 9,
                color: secondaryTextColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Earning guide
  Widget _buildEarningGuide() {
    final isDark = context.isDarkMode;
    final cardColor = context.cardColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;
    final primaryColor = context.primaryColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tips_and_updates, color: primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'How to Earn Points',
                style: context.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Complete simple actions to earn points',
            style: context.bodySmall.copyWith(color: secondaryTextColor),
          ),
          const SizedBox(height: 16),
          _buildEarningRow(
            Icons.event_available,
            'Complete a booking',
            'Earn 1 point per Rs. 10 spent',
            AppTheme.success,
          ),
          const SizedBox(height: 12),
          _buildEarningRow(
            Icons.rate_review,
            'Write a review',
            '+10 points per review',
            Colors.blue,
          ),
          const SizedBox(height: 12),
          _buildEarningRow(
            Icons.people,
            'Refer a friend',
            'Earn bonus points on first booking',
            Colors.purple,
          ),
          const SizedBox(height: 12),
          _buildEarningRow(
            Icons.cake,
            'Birthday bonus',
            'Special points on your birthday',
            Colors.pink,
          ),
          const SizedBox(height: 12),
          _buildEarningRow(
            Icons.local_offer,
            'Claim special offers',
            'Redeem points for exclusive offers',
            AppTheme.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildEarningRow(
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: context.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              Text(
                subtitle,
                style: context.bodySmall.copyWith(color: secondaryTextColor),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================
  // TAB 3: HISTORY
  // ============================================

  Widget _buildHistoryTab() {
    final isDark = context.isDarkMode;
    final secondaryTextColor = context.secondaryTextColor;

    if (_transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 64,
                color: isDark ? Colors.white30 : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No transactions yet',
                style: context.titleMedium.copyWith(
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start earning points by booking services!',
                style: context.bodySmall.copyWith(color: secondaryTextColor),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLoyaltyData,
      color: context.primaryColor,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(_isWeb ? 24 : 16),
        itemCount: _transactions.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final tx = _transactions[index];
          return _buildTransactionCard(tx);
        },
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final isDark = context.isDarkMode;
    final cardColor = context.cardColor;
    final secondaryTextColor = context.secondaryTextColor;

    final type = tx['type']?.toString() ?? 'earn';
    final source = tx['source']?.toString() ?? 'booking';
    final points = (tx['points'] as num?)?.toInt() ?? 0;
    final description = tx['description']?.toString() ?? '';
    final createdAt = tx['created_at'] != null
        ? DateTime.tryParse(tx['created_at'].toString())
        : null;

    final color = _txColor(type);
    final isPositive = points > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _txIcon(type, source),
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _txLabel(type),
                      style: context.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _sourceLabel(source),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: context.bodySmall.copyWith(color: secondaryTextColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (createdAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM dd, yyyy • HH:mm').format(createdAt),
                    style: context.bodySmall.copyWith(
                      fontSize: 10,
                      color: isDark ? Colors.white38 : Colors.grey[500],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${isPositive ? '+' : ''}$points',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: isPositive ? AppTheme.success : AppTheme.warning,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // TAB 4: BADGES
  // ============================================

  Widget _buildBadgesTab() {
    final isDark = context.isDarkMode;

    if (_badges.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.emoji_events_outlined,
                size: 64,
                color: isDark ? Colors.white30 : Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No badges available yet',
                style: context.titleMedium.copyWith(
                  color: isDark ? Colors.white70 : Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final earned = _badges.where((b) => _isBadgeEarned(b['id'])).toList();
    final locked = _badges.where((b) => !_isBadgeEarned(b['id'])).toList();

    return RefreshIndicator(
      onRefresh: _loadLoyaltyData,
      color: context.primaryColor,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(_isWeb ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: AppTheme.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Earn badges by completing achievements. Collect all badges to show off your loyalty!',
                      style: context.bodySmall.copyWith(
                        color: context.textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Earned section
            if (earned.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(
                    Icons.emoji_events,
                    color: AppTheme.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Earned Badges (${earned.length})',
                    style: context.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...earned.map((b) => _buildBadgeCard(b, isEarned: true)),
              const SizedBox(height: 24),
            ],

            // Locked section
            if (locked.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.lock_outline,
                    color: isDark ? Colors.white60 : Colors.grey[600],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Available Badges (${locked.length})',
                    style: context.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...locked.map((b) => _buildBadgeCard(b, isEarned: false)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadgeCard(
    Map<String, dynamic> badge, {
    required bool isEarned,
  }) {
    final isDark = context.isDarkMode;
    final cardColor = context.cardColor;
    final textColor = context.textColor;
    final secondaryTextColor = context.secondaryTextColor;

    final name = badge['name']?.toString() ?? 'Badge';
    final description = badge['description']?.toString() ?? '';
    final pointsRequired = (badge['points_required'] as num?)?.toInt() ?? 0;
    final bookingsRequired = (badge['bookings_required'] as num?)?.toInt() ?? 0;
    final earnedAt = isEarned ? _getBadgeEarnedDate(badge['id']) : null;

    final cardColorValue = isEarned ? AppTheme.warning : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isEarned
              ? cardColorValue.withValues(alpha: 0.4)
              : (isDark ? Colors.grey[700]! : Colors.grey[200]!),
          width: isEarned ? 1.5 : 1,
        ),
        boxShadow: isEarned
            ? [
                BoxShadow(
                  color: cardColorValue.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: cardColorValue.withValues(alpha: isEarned ? 0.15 : 0.08),
              shape: BoxShape.circle,
              border: Border.all(
                color: cardColorValue.withValues(alpha: isEarned ? 0.5 : 0.2),
                width: 2,
              ),
            ),
            child: Icon(
              isEarned ? Icons.emoji_events : Icons.lock,
              color: isEarned
                  ? cardColorValue
                  : (isDark ? Colors.white38 : Colors.grey[400]),
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: context.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ),
                    if (isEarned)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '✓ EARNED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.warning,
                          ),
                        ),
                      ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: context.bodySmall.copyWith(color: secondaryTextColor),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                if (!isEarned) ...[
                  Text(
                    'To unlock:',
                    style: context.bodySmall.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (pointsRequired > 0)
                        _buildRequirementChip(
                          Icons.stars,
                          '$pointsRequired pts',
                          isDark,
                        ),
                      if (bookingsRequired > 0)
                        _buildRequirementChip(
                          Icons.event_available,
                          '$bookingsRequired bookings',
                          isDark,
                        ),
                    ],
                  ),
                ] else if (earnedAt != null) ...[
                  Text(
                    'Earned on ${DateFormat('MMM dd, yyyy').format(earnedAt)}',
                    style: context.bodySmall.copyWith(
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white38 : Colors.grey[500],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementChip(IconData icon, String text, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: isDark ? Colors.white60 : Colors.grey[600],
          ),
          const SizedBox(width: 3),
          Text(
            text,
            style: context.bodySmall.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white60 : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}