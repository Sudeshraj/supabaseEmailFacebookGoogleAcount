import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/alertBox/show_logout_conf.dart';
import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/services/notification_service.dart';
import 'package:flutter_application_1/services/permission_service.dart';
import 'package:flutter_application_1/screens/settings/permission_manager.dart';
import 'package:flutter_application_1/services/session_manager.dart';
import 'package:flutter_application_1/widgets/permission_card.dart';
import 'package:flutter_application_1/widgets/side_menu.dart';
import 'package:flutter_application_1/widgets/dashboard_stat_card.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_platform/universal_platform.dart';
import '../../services/timezone_service.dart';

final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({super.key});

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard>
    with SingleTickerProviderStateMixin, RouteAware {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final NotificationService _notificationService = NotificationService();
  final PermissionService _permissionService = PermissionService();
  final PermissionManager _permissionManager = PermissionManager();

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  bool _hasPermission = false;
  bool _showPermissionCard = false;
  bool _isLoading = true;
  bool _isSwitchingSalon = false;

  // Dashboard data
  int completedToday = 0;
  int pendingAppointments = 0;
  int _pendingBookings = 0;
  int _todayAppointments = 0;
  int _totalRevenue = 0;
  int _totalCustomers = 0;
  int _activeBarbers = 0;

  // Multiple salons support
  List<Map<String, dynamic>> _ownerSalons = [];
  String? _selectedSalonId;

  // User info
  String _userName = 'Salon Owner';
  String? _userEmail;
  String? _profileImageUrl;

  // Timezone
  String _currentTimezone = '';
  String _currentTimezoneFlag = '';
  String _currentTimezoneOffset = '';
  String _currentDate = '';

  // Onboarding steps
  int _completedSteps = 0;
  final int _totalSteps = 5;
  bool _hasSalon = false;
  bool _hasServices = false;
  bool _hasBarbers = false;
  bool _hasBarberSchedule = false;
  bool _hasHolidays = false;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.06,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    
    _initializeAndLoad();
    _setupNotificationListeners();
  }

  // ✅ Initialize and load data with role fix
  Future<void> _initializeAndLoad() async {
    await _ensureOwnerRole();
    await _loadAllData();
  }

  // ✅ Ensure user has owner role
  Future<void> _ensureOwnerRole() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ No user logged in');
        return;
      }

      debugPrint('🔍 Ensuring owner role for user: $userId');

      final ownerCheck = await supabase
          .from('user_roles')
          .select('id, status')
          .eq('user_id', userId)
          .eq('role_id', 1)
          .maybeSingle();

      if (ownerCheck == null) {
        debugPrint('🔄 Creating owner role...');
        await supabase.from('user_roles').insert({
          'user_id': userId,
          'role_id': 1,
          'status': 'active'
        });
        debugPrint('✅ Owner role created');
      } else if (ownerCheck['status'] != 'active') {
        debugPrint('🔄 Updating owner role to active...');
        await supabase
            .from('user_roles')
            .update({'status': 'active', 'updated_at': DateTime.now().toIso8601String()})
            .eq('user_id', userId)
            .eq('role_id', 1);
        debugPrint('✅ Owner role activated');
      } else {
        debugPrint('✅ Owner role already active');
      }

      // Also ensure barber and customer roles exist
      for (var roleId in [2, 3]) {
        final check = await supabase
            .from('user_roles')
            .select('id, status')
            .eq('user_id', userId)
            .eq('role_id', roleId)
            .maybeSingle();

        if (check == null) {
          await supabase.from('user_roles').insert({
            'user_id': userId,
            'role_id': roleId,
            'status': 'active'
          });
          debugPrint('✅ Role $roleId created');
        } else if (check['status'] != 'active') {
          await supabase
              .from('user_roles')
              .update({'status': 'active', 'updated_at': DateTime.now().toIso8601String()})
              .eq('user_id', userId)
              .eq('role_id', roleId);
          debugPrint('✅ Role $roleId activated');
        }
      }

      await supabase.auth.refreshSession();
      debugPrint('✅ Session refreshed');

    } catch (e) {
      debugPrint('❌ Error ensuring owner role: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    debugPrint('🔄 Dashboard: Returning from child screen, refreshing data');
    _refreshAllData();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // 🔥 SHOW PERMISSION CARD - WITH CONTEXT
  // ============================================================

  Future<void> _showPermissionCardContext({String? action}) async {
    final shouldShow = await _permissionManager.shouldShowPermissionCard(
      screen: 'owner_dashboard',
      action: action,
    );

    if (mounted) {
      setState(() {
        _showPermissionCard = shouldShow;
      });
    }
  }

  // ============================================================
  // 🔥 ENABLE NOTIFICATIONS - WITH CONTEXT
  // ============================================================

  Future<void> _enableNotifications({String? action}) async {
    setState(() => _showPermissionCard = false);

    try {
      final bool isWeb = UniversalPlatform.isWeb;

      if (isWeb) {
        final status = await _notificationService.getWebPermissionStatus();
        if (status == 'denied') {
          if (mounted) {
            _showWebPermissionHelp();
          }
          return;
        }
      }

      final canAsk = await _permissionManager.canAskSystemPermission();
      if (!canAsk) {
        if (mounted) {
          _showSettingsDialog();
        }
        return;
      }

      if (!mounted) return;

      await _permissionService.requestPermissionAtAction(
        context: context,
        action: action ?? 'owner_dashboard',
        customTitle: _permissionManager.getPermissionCardTitle(action: action),
        customMessage: _permissionManager.getPermissionCardMessage(
          action: action,
        ),
        onGranted: () async {
          debugPrint('✅ Permission granted callback');
          await _permissionManager.markPermissionGranted();

          if (mounted) {
            setState(() {
              _hasPermission = true;
              _showPermissionCard = false;
            });

            final message = isWeb
                ? '✅ Notifications enabled in browser!'
                : '✅ Notifications enabled!';

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 3),
              ),
            );

            _refreshAllData();
          }
        },
        onDenied: () async {
          debugPrint('❌ Permission denied callback');
          await _permissionManager.markPermissionDenied(permanent: false);

          if (mounted) {
            final message = isWeb
                ? 'You can enable notifications later from browser settings'
                : 'You can enable later from settings';

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
      );
    } catch (e) {
      debugPrint('❌ Error enabling notifications: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================================
  // 🔥 SHOW WEB PERMISSION HELP
  // ============================================================

  void _showWebPermissionHelp() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🌐'),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Browser Notification Settings',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'To enable notifications, please follow these steps:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildWebStep('1', 'Click the 🔒 lock icon in the address bar'),
              const SizedBox(height: 8),
              _buildWebStep('2', 'Click "Site settings" or "Permissions"'),
              const SizedBox(height: 8),
              _buildWebStep('3', 'Find "Notifications" and select "Allow"'),
              const SizedBox(height: 8),
              _buildWebStep('4', 'Refresh the page'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Once enabled, you\'ll receive notifications even when the tab is not active',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _permissionService.refreshWebPage();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 36),
            ),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Refresh Page'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebStep(String number, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B8B).withAlpha(20),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF6B8B),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🔔 Notifications Disabled'),
        content: const Text(
          'To enable notifications, please go to your device settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _permissionService.openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleNotNow() async {
    setState(() => _showPermissionCard = false);
    await _permissionManager.markPermissionShown('owner_dashboard');
  }

  // ============================================================
  // 🔥 CONTEXTUAL ACTIONS - SHOW PERMISSION CARD
  // ============================================================

  void _viewBookings() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'booking');
      if (_showPermissionCard) return;
    }
    if (_selectedSalonId != null) {
      context.push('/owner/appointments?salonId=$_selectedSalonId');
    } else {
      context.push('/owner/appointments');
    }
  }

  void _navigateToOffers() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'offer');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    if (_selectedSalonId != null) {
      context.push('/owner/offers/$_selectedSalonId');
    } else {
      context.push('/owner/offers');
    }
  }

  void _navigateToAddBarber() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'barber');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    context.push('/owner/add-barber?salonId=$_selectedSalonId');
  }

  void _navigateToAddService() async {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'booking');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    final result = await context.push(
      '/owner/services/add?salonId=$_selectedSalonId',
    );
    if (result == true) await _refreshAllData();
  }

  void _navigateToBarberLeaves() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'barber');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    context.push('/owner/barber-leaves?salonId=$_selectedSalonId');
  }

  void _navigateToBarberSchedule() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'barber');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    context.push('/owner/barber-schedule?salonId=$_selectedSalonId');
  }

  void _navigateToBarberList() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'barber');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    context.push('/owner/barbers?salonId=$_selectedSalonId');
  }

  void _navigateToServiceList() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'booking');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    if (_ownerSalons.length == 1) {
      final salon = _ownerSalons.first;
      context.push(
        '/owner/services?salonId=${salon['id']}&salonName=${Uri.encodeComponent(salon['name'])}',
      );
    } else {
      _showSalonSelectionDialogForServices();
    }
  }

  void _viewAllCustomers() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'booking');
      if (_showPermissionCard) return;
    }
    if (_selectedSalonId != null) {
      context.push('/owner/customers?salonId=$_selectedSalonId');
    } else {
      context.push('/owner/customers');
    }
  }

  void _viewRevenue() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'booking');
      if (_showPermissionCard) return;
    }
    if (_selectedSalonId != null) {
      context.push('/owner/revenue?salonId=$_selectedSalonId');
    } else {
      context.push('/owner/revenue');
    }
  }

  void _viewSalonHolidays() {
    if (!_hasPermission) {
      _showPermissionCardContext(action: 'booking');
      if (_showPermissionCard) return;
    }
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    context.push('/owner/salon/holidays?salonId=$_selectedSalonId');
  }

  // ============================================================
  // TIMEZONE METHODS
  // ============================================================

  void _updateCurrentDate() {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final weekdays = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    _currentDate =
        '${weekdays[now.weekday]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
  }

  Future<void> _loadTimezone() async {
    await TimezoneService.initialize();
    final prefs = await SharedPreferences.getInstance();

    final cachedTimezone = prefs.getString('cached_timezone');
    if (cachedTimezone != null && cachedTimezone.isNotEmpty) {
      _currentTimezone = cachedTimezone;
    } else {
      _currentTimezone = TimezoneService.getCurrentTimezone();
      await prefs.setString('cached_timezone', _currentTimezone);
    }

    _currentTimezoneFlag = TimezoneService.getCurrentFlag();
    _currentTimezoneOffset = TimezoneService.getUtcOffsetString();
    _updateCurrentDate();
  }

  // ============================================================
  // TIMEZONE PICKER
  // ============================================================

  String _extractCountryCode(String timezone) {
    final countryMap = {
      'Asia/Colombo': 'LK',
      'Asia/Tokyo': 'JP',
      'Asia/Seoul': 'KR',
      'Asia/Shanghai': 'CN',
      'Asia/Hong_Kong': 'HK',
      'Asia/Taipei': 'TW',
      'Asia/Kolkata': 'IN',
      'Asia/Dubai': 'AE',
      'Asia/Singapore': 'SG',
      'Asia/Kuala_Lumpur': 'MY',
      'Asia/Bangkok': 'TH',
      'Asia/Jakarta': 'ID',
      'Asia/Manila': 'PH',
      'Asia/Ho_Chi_Minh': 'VN',
      'Asia/Dhaka': 'BD',
      'Asia/Karachi': 'PK',
      'Asia/Kathmandu': 'NP',
      'Asia/Riyadh': 'SA',
      'Asia/Kuwait': 'KW',
      'Asia/Doha': 'QA',
      'Europe/London': 'GB',
      'Europe/Paris': 'FR',
      'Europe/Berlin': 'DE',
      'Europe/Rome': 'IT',
      'Europe/Madrid': 'ES',
      'Europe/Amsterdam': 'NL',
      'Europe/Zurich': 'CH',
      'Europe/Moscow': 'RU',
      'America/New_York': 'US',
      'America/Chicago': 'US',
      'America/Denver': 'US',
      'America/Los_Angeles': 'US',
      'America/Toronto': 'CA',
      'America/Vancouver': 'CA',
      'America/Mexico_City': 'MX',
      'America/Sao_Paulo': 'BR',
      'Australia/Sydney': 'AU',
      'Australia/Melbourne': 'AU',
      'Australia/Perth': 'AU',
      'Australia/Adelaide': 'AU',
      'Pacific/Auckland': 'NZ',
      'Africa/Johannesburg': 'ZA',
      'Africa/Cairo': 'EG',
      'Africa/Lagos': 'NG',
      'Africa/Nairobi': 'KE',
      'America/Argentina/Buenos_Aires': 'AR',
      'America/Santiago': 'CL',
      'America/Bogota': 'CO',
      'America/Lima': 'PE',
    };
    if (countryMap.containsKey(timezone)) return countryMap[timezone]!;
    for (var entry in countryMap.entries) {
      if (timezone.contains(entry.key) || entry.key.contains(timezone)) {
        return entry.value;
      }
    }
    return '';
  }

  String _getFlagByCountryCode(String countryCode) {
    final flags = {
      'LK': '🇱🇰',
      'JP': '🇯🇵',
      'KR': '🇰🇷',
      'CN': '🇨🇳',
      'HK': '🇭🇰',
      'TW': '🇹🇼',
      'IN': '🇮🇳',
      'AE': '🇦🇪',
      'SG': '🇸🇬',
      'MY': '🇲🇾',
      'TH': '🇹🇭',
      'ID': '🇮🇩',
      'PH': '🇵🇭',
      'VN': '🇻🇳',
      'BD': '🇧🇩',
      'PK': '🇵🇰',
      'NP': '🇳🇵',
      'SA': '🇸🇦',
      'KW': '🇰🇼',
      'QA': '🇶🇦',
      'GB': '🇬🇧',
      'FR': '🇫🇷',
      'DE': '🇩🇪',
      'IT': '🇮🇹',
      'ES': '🇪🇸',
      'NL': '🇳🇱',
      'CH': '🇨🇭',
      'RU': '🇷🇺',
      'US': '🇺🇸',
      'CA': '🇨🇦',
      'MX': '🇲🇽',
      'BR': '🇧🇷',
      'AU': '🇦🇺',
      'NZ': '🇳🇿',
      'ZA': '🇿🇦',
      'EG': '🇪🇬',
      'NG': '🇳🇬',
      'KE': '🇰🇪',
      'AR': '🇦🇷',
      'CL': '🇨🇱',
      'CO': '🇨🇴',
      'PE': '🇵🇪',
    };
    return flags[countryCode] ?? '🌐';
  }

  Map<String, List<String>> _groupTimezonesByContinent(List<String> timezones) {
    final groups = <String, List<String>>{};
    for (final tz in timezones) {
      final parts = tz.split('/');
      if (parts.length >= 2) {
        final continent = parts[0];
        if (!groups.containsKey(continent)) groups[continent] = [];
        groups[continent]!.add(tz);
      } else {
        if (!groups.containsKey('UTC')) groups['UTC'] = [];
        groups['UTC']!.add(tz);
      }
    }
    for (final key in groups.keys) {
      groups[key]!.sort();
    }
    return groups;
  }

  Widget _buildTimezoneTile(String tz, String displayName, String flag) {
    final isSelected = tz == _currentTimezone;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFFFF6B8B).withValues(alpha: 0.1)
            : null,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: isSelected
              ? const Color(0xFFFF6B8B)
              : Colors.grey[200],
          child: Text(flag, style: const TextStyle(fontSize: 16)),
        ),
        title: Text(
          displayName,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? const Color(0xFFFF6B8B) : null,
          ),
        ),
        subtitle: Text(
          tz,
          style: const TextStyle(fontSize: 11),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: Color(0xFFFF6B8B))
            : null,
        onTap: () => Navigator.of(context).pop(tz),
      ),
    );
  }

  Widget _buildCurrentTimezoneInfo() {
    final displayName = _currentTimezone.split('/').last.replaceAll('_', ' ');
    final offset = TimezoneService.getUtcOffsetString();
    final flag = TimezoneService.getCurrentFlag();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(flag, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current: $displayName',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  _currentTimezone,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              offset,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: Color(0xFFFF6B8B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.access_time,
              color: Color(0xFFFF6B8B),
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Select Your Timezone',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF6B8B),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _changeTimezone() async {
    final allTimezones = TimezoneService.getAllAvailableTimezones();
    final continentGroups = _groupTimezonesByContinent(allTimezones);

    final List<Map<String, dynamic>> searchableList = [];
    for (var entry in continentGroups.entries) {
      final continent = entry.key;
      for (final tz in entry.value) {
        final displayName = tz.split('/').last.replaceAll('_', ' ');
        final countryCode = _extractCountryCode(tz);
        final flag = _getFlagByCountryCode(countryCode);

        final searchText = [
          continent.toLowerCase(),
          displayName.toLowerCase(),
          tz.toLowerCase(),
          countryCode.toLowerCase(),
          displayName.toLowerCase(),
        ].join(' ');

        searchableList.add({
          'timezone': tz,
          'displayName': displayName,
          'continent': continent,
          'flag': flag,
          'searchText': searchText,
        });
      }
    }

    TextEditingController searchController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        String searchQuery = '';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            List<Map<String, dynamic>> filteredList = searchableList;
            if (searchQuery.isNotEmpty) {
              final query = searchQuery.toLowerCase();
              filteredList = searchableList
                  .where((item) => item['searchText'].contains(query))
                  .toList();
            }

            Map<String, List<Map<String, dynamic>>> filteredGroups = {};
            for (var item in filteredList) {
              final continent = item['continent'];
              if (!filteredGroups.containsKey(continent)) {
                filteredGroups[continent] = [];
              }
              filteredGroups[continent]!.add(item);
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                height: MediaQuery.of(context).size.height * 0.85,
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDialogHeader(),
                    const Divider(),
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 12),
                      child: TextField(
                        controller: searchController,
                        autofocus: false,
                        onChanged: (value) {
                          setDialogState(() {
                            searchQuery = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText:
                              '🔍 Search by country, city, or timezone...',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Colors.grey,
                          ),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () {
                                    searchController.clear();
                                    setDialogState(() {
                                      searchQuery = '';
                                    });
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    if (searchQuery.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Found ${filteredList.length} timezone${filteredList.length != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    Expanded(
                      child: searchQuery.isEmpty
                          ? DefaultTabController(
                              length: continentGroups.keys.length,
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 45,
                                    child: TabBar(
                                      isScrollable: true,
                                      labelColor: const Color(0xFFFF6B8B),
                                      unselectedLabelColor: Colors.grey,
                                      indicatorColor: const Color(0xFFFF6B8B),
                                      labelStyle: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                      tabs: continentGroups.keys
                                          .map(
                                            (continent) => Tab(text: continent),
                                          )
                                          .toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: TabBarView(
                                      children: continentGroups.values.map((
                                        timezones,
                                      ) {
                                        return ListView.builder(
                                          itemCount: timezones.length,
                                          itemBuilder: (context, index) {
                                            final tz = timezones[index];
                                            final displayName = tz
                                                .split('/')
                                                .last
                                                .replaceAll('_', ' ');
                                            final countryCode =
                                                _extractCountryCode(tz);
                                            final flag = _getFlagByCountryCode(
                                              countryCode,
                                            );
                                            return _buildTimezoneTile(
                                              tz,
                                              displayName,
                                              flag,
                                            );
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : filteredList.isNotEmpty
                          ? ListView.builder(
                              itemCount: filteredGroups.keys.length,
                              itemBuilder: (context, index) {
                                final continent = filteredGroups.keys.elementAt(
                                  index,
                                );
                                final items = filteredGroups[continent]!;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _getContinentEmoji(continent),
                                            style: const TextStyle(
                                              fontSize: 18,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            continent,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                          ),
                                          Container(
                                            margin: const EdgeInsets.only(
                                              left: 8,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[200],
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            child: Text(
                                              '${items.length}',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ...items.map(
                                      (item) => _buildTimezoneTile(
                                        item['timezone'],
                                        item['displayName'],
                                        item['flag'],
                                      ),
                                    ),
                                    if (index != filteredGroups.keys.length - 1)
                                      const Divider(),
                                  ],
                                );
                              },
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.search_off,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No timezones found',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Try "Sri Lanka", "Tokyo", "London", or "New York"',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    _buildCurrentTimezoneInfo(),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null && result != _currentTimezone) {
      await _applyTimezoneChange(result);
    }
  }

  Future<void> _applyTimezoneChange(String newTimezone) async {
    setState(() => _isLoading = true);

    try {
      await TimezoneService.setTimezone(newTimezone);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_timezone', newTimezone);

      _currentTimezone = newTimezone;
      _currentTimezoneFlag = TimezoneService.getCurrentFlag();
      _currentTimezoneOffset = TimezoneService.getUtcOffsetString();

      await _loadAllData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Timezone changed to ${newTimezone.split('/').last.replaceAll('_', ' ')}',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error changing timezone: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error changing timezone: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getContinentEmoji(String continent) {
    final emojis = {
      'Asia': '🌏',
      'Europe': '🌍',
      'Africa': '🌍',
      'America': '🌎',
      'Australia': '🇦🇺',
      'Pacific': '🌏',
      'UTC': '🌐',
    };
    return emojis[continent] ?? '🌐';
  }

  // ============================================================
  // LOAD DATA
  // ============================================================

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      await _loadTimezone();
      
      await _loadUserProfile();
      
      await _loadOwnerSalons();
      
      // ✅ Load dashboard stats with error handling
      try {
        await _loadDashboardStats();
      } catch (e) {
        debugPrint('⚠️ Dashboard stats error (non-critical): $e');
        if (mounted) {
          setState(() {
            _todayAppointments = 0;
            _pendingBookings = 0;
            _activeBarbers = 0;
            _totalCustomers = 0;
            _totalRevenue = 0;
            pendingAppointments = 0;
            completedToday = 0;
          });
        }
      }
      
      // ✅ Check onboarding status with error handling
      try {
        await _checkOnboardingStatus();
      } catch (e) {
        debugPrint('⚠️ Onboarding status error (non-critical): $e');
      }

      _hasPermission = await _notificationService.hasPermission();

      if (!_hasPermission) {
        _showPermissionCard = await _permissionManager.shouldShowPermissionCard(
          screen: 'owner_dashboard',
          action: null,
        );

        if (UniversalPlatform.isWeb && _showPermissionCard) {
          final status = await _notificationService.getWebPermissionStatus();
          if (status == 'denied') {
            _showPermissionCard = false;
            if (mounted) {
              _showWebPermissionHelp();
            }
          }
        }
      } else {
        _showPermissionCard = false;
      }

      if (mounted) setState(() => _isLoading = false);
      
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ✅ FIX 5: Load Owner Salons with auto-creation
  Future<void> _loadOwnerSalons() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      debugPrint('🔍 Current User ID: $userId');
      debugPrint('🔍 Current User Email: ${supabase.auth.currentUser?.email}');
      
      if (userId == null) {
        debugPrint('❌ No user logged in');
        if (mounted) {
          setState(() {
            _ownerSalons = [];
            _hasSalon = false;
          });
        }
        return;
      }

      // ✅ Check and ensure owner role
      final ownerCheck = await supabase
          .from('user_roles')
          .select('''
            id,
            role_id,
            status,
            roles!inner (
              id,
              name,
              description
            )
          ''')
          .eq('user_id', userId)
          .eq('role_id', 1)
          .maybeSingle();

      debugPrint('🔍 Owner role check: $ownerCheck');

      if (ownerCheck == null) {
        debugPrint('🔄 Creating owner role...');
        try {
          await supabase.from('user_roles').insert({
            'user_id': userId,
            'role_id': 1,
            'status': 'active'
          });
          debugPrint('✅ Owner role created');
        } catch (createError) {
          debugPrint('❌ Error creating owner role: $createError');
        }
      } else if (ownerCheck['status'] != 'active') {
        debugPrint('🔄 Updating owner role to active...');
        try {
          await supabase
              .from('user_roles')
              .update({'status': 'active', 'updated_at': DateTime.now().toIso8601String()})
              .eq('user_id', userId)
              .eq('role_id', 1);
          debugPrint('✅ Owner role activated');
        } catch (updateError) {
          debugPrint('❌ Error updating owner role: $updateError');
        }
      } else {
        debugPrint('✅ User has active owner role');
      }

      // ✅ Load salons
      debugPrint('🔍 Loading salons for owner: $userId');
      
      final response = await supabase
          .from('salons')
          .select('''
            id,
            name,
            address,
            phone,
            email,
            description,
            is_active,
            created_at,
            updated_at,
            logo_url,
            cover_url,
            open_time,
            close_time,
            timezone
          ''')
          .eq('owner_id', userId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      debugPrint('🔍 Found ${response.length} salons');
      debugPrint('🔍 Salon names: ${response.map((s) => s['name']).toList()}');

      if (mounted) {
        setState(() {
          _ownerSalons = List<Map<String, dynamic>>.from(response);
          if (_ownerSalons.isNotEmpty) {
            _hasSalon = true;
            if (_selectedSalonId == null) {
              _selectedSalonId = _ownerSalons.first['id'].toString();
              debugPrint('✅ Selected first salon: ${_ownerSalons.first['name']} (ID: $_selectedSalonId)');
            }
          } else {
            _hasSalon = false;
            debugPrint('⚠️ No active salons found for this owner');
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading salons: $e');
      debugPrint('📚 Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _ownerSalons = [];
          _hasSalon = false;
        });
      }
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final profileCheck = await supabase
          .from('profiles')
          .select('is_active, is_blocked')
          .eq('id', currentUser.id)
          .maybeSingle();

      if (profileCheck != null) {
        if (profileCheck['is_blocked'] == true) {
          debugPrint('⚠️ User account is blocked');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your account has been blocked. Please contact support.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        if (profileCheck['is_active'] == false) {
          debugPrint('⚠️ User profile is inactive');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Your profile is inactive. Please contact support.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      final profileResponse = await supabase
          .from('profiles')
          .select('full_name, email, avatar_url, extra_data')
          .eq('id', currentUser.id)
          .maybeSingle();

      if (profileResponse != null && mounted) {
        setState(() {
          _userName =
              profileResponse['full_name'] ??
              profileResponse['extra_data']?['full_name'] ??
              'Salon Owner';
          _userEmail = profileResponse['email'] ?? currentUser.email;
          _profileImageUrl = profileResponse['avatar_url'];
        });
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
    }
  }

  // ✅ FIX 5: Load Dashboard Stats - SIMPLEST APPROACH
  Future<void> _loadDashboardStats() async {
    if (_selectedSalonId == null || _ownerSalons.isEmpty) return;
    
    try {
      final today = DateTime.now().toIso8601String().split('T')[0];
      final salonIdInt = int.parse(_selectedSalonId!);

      // 1. Today's appointments
      final todayAppointments = await supabase
          .from('appointments')
          .select('id, status, price')
          .eq('salon_id', salonIdInt)
          .eq('appointment_date', today);

      // 2. Pending bookings
      final pendingBookings = await supabase
          .from('appointments')
          .select('id')
          .eq('salon_id', salonIdInt)
          .eq('appointment_date', today)
          .eq('status', 'pending');

      // ✅ 3. ACTIVE BARBERS - SIMPLEST APPROACH (FIX 5)
      // Step 1: Get all active barbers from salon_barbers
      final activeBarbers = await supabase
          .from('salon_barbers')
          .select('barber_id')
          .eq('salon_id', salonIdInt)
          .eq('status', 'active');
      
      // Step 2: Count how many have active user_roles
      int activeBarberCount = 0;
      if (activeBarbers.isNotEmpty) {
        final barberIds = activeBarbers.map((b) => b['barber_id'] as String).toList();
        
        final validBarbers = await supabase
            .from('user_roles')
            .select('user_id')
            .inFilter('user_id', barberIds)
            .eq('role_id', 2) // barber role
            .eq('status', 'active');
        
        activeBarberCount = validBarbers.length;
      }

      // 4. Total customers (unique)
      final totalCustomers = await supabase
          .from('appointments')
          .select('customer_id')
          .eq('salon_id', salonIdInt);

      final uniqueCustomers = totalCustomers
          .map((a) => a['customer_id'] as String)
          .toSet()
          .length;
          
      // 5. Revenue
      final revenue = todayAppointments.fold<int>(
        0,
        (sum, item) => sum + ((item['price'] as num?)?.toInt() ?? 0),
      );

      if (mounted) {
        setState(() {
          _todayAppointments = todayAppointments.length;
          _pendingBookings = pendingBookings.length;
          _activeBarbers = activeBarberCount;
          _totalCustomers = uniqueCustomers;
          _totalRevenue = revenue;
          pendingAppointments = _pendingBookings;
          completedToday = todayAppointments
              .where((a) => a['status'] == 'completed')
              .length;
        });
      }
      
      debugPrint('📊 Stats: Today: $_todayAppointments, Pending: $_pendingBookings, Barbers: $_activeBarbers');
      
    } catch (e) {
      debugPrint('❌ Dashboard stats error: $e');
      if (mounted) {
        setState(() {
          _todayAppointments = 0;
          _pendingBookings = 0;
          _activeBarbers = 0;
          _totalCustomers = 0;
          _totalRevenue = 0;
          pendingAppointments = 0;
          completedToday = 0;
        });
      }
    }
  }

  // ✅ FIX 5: Check Onboarding Status - SIMPLEST APPROACH
  Future<void> _checkOnboardingStatus() async {
    if (_ownerSalons.isEmpty || _selectedSalonId == null) {
      setState(() {
        _hasSalon = false;
        _hasServices = false;
        _hasBarbers = false;
        _hasBarberSchedule = false;
        _hasHolidays = false;
        _completedSteps = 0;
      });
      return;
    }

    try {
      final salonId = int.parse(_selectedSalonId!);

      // 1. Check services
      final servicesResponse = await supabase
          .from('services')
          .select('id')
          .eq('salon_id', salonId)
          .eq('is_active', true)
          .limit(1);
      _hasServices = servicesResponse.isNotEmpty;

      // ✅ 2. CHECK BARBERS - SIMPLEST APPROACH (FIX 5)
      final barbers = await supabase
          .from('salon_barbers')
          .select('barber_id')
          .eq('salon_id', salonId)
          .eq('status', 'active');
      
      bool hasActiveBarbers = false;
      if (barbers.isNotEmpty) {
        final barberIds = barbers.map((b) => b['barber_id'] as String).toList();
        
        final validBarbers = await supabase
            .from('user_roles')
            .select('user_id')
            .inFilter('user_id', barberIds)
            .eq('role_id', 2)
            .eq('status', 'active')
            .limit(1);
        
        hasActiveBarbers = validBarbers.isNotEmpty;
      }
      _hasBarbers = hasActiveBarbers;

      // 3. Check barber schedules
      if (_hasBarbers) {
        final schedulesResponse = await supabase
            .from('barber_schedules')
            .select('id')
            .eq('salon_id', salonId)
            .limit(1);
        _hasBarberSchedule = schedulesResponse.isNotEmpty;
      } else {
        _hasBarberSchedule = false;
      }

      // 4. Check holidays
      final holidaysResponse = await supabase
          .from('salon_holidays')
          .select('id')
          .eq('salon_id', salonId)
          .limit(1);
      _hasHolidays = holidaysResponse.isNotEmpty;

      if (mounted) {
        setState(() {
          _hasSalon = true;
          _completedSteps =
              (_hasSalon ? 1 : 0) +
              (_hasServices ? 1 : 0) +
              (_hasBarbers ? 1 : 0) +
              (_hasBarberSchedule ? 1 : 0) +
              (_hasHolidays ? 1 : 0);
        });
      }
      
      debugPrint('📊 Onboarding: Salon: $_hasSalon, Services: $_hasServices, Barbers: $_hasBarbers');
      
    } catch (e) {
      debugPrint('❌ Onboarding error: $e');
    }
  }

  Future<void> _refreshAllData() async => _loadAllData();

  Future<void> _switchSalon(String salonId) async {
    if (_isSwitchingSalon || salonId == _selectedSalonId) return;

    setState(() {
      _isSwitchingSalon = true;
      _selectedSalonId = salonId;
    });

    try {
      await Future.wait([_loadDashboardStats(), _checkOnboardingStatus()]);
    } catch (e) {
      debugPrint('Error switching salon: $e');
    } finally {
      if (mounted) setState(() => _isSwitchingSalon = false);
    }
  }

  // ============================================================
  // SALON SETUP STEP FLOW
  // ============================================================

  Widget _buildStepFlow() {
    final steps = [
      {
        'label': 'Create Salon',
        'subtitle': 'Set up your profile',
        'isCompleted': _hasSalon,
        'onTap': _navigateToCreateSalon,
        'icon': Icons.storefront_outlined,
        'locked': false,
      },
      {
        'label': 'Add Services',
        'subtitle': 'Services & pricing',
        'isCompleted': _hasServices,
        'onTap': _navigateToAddService,
        'icon': Icons.content_cut_outlined,
        'locked': !_hasSalon,
      },
      {
        'label': 'Add Barbers',
        'subtitle': 'Your team',
        'isCompleted': _hasBarbers,
        'onTap': _navigateToAddBarber,
        'icon': Icons.people_outline,
        'locked': !_hasSalon,
      },
      {
        'label': 'Set Schedules',
        'subtitle': 'Working hours',
        'isCompleted': _hasBarberSchedule,
        'onTap': _navigateToBarberSchedule,
        'icon': Icons.calendar_month_outlined,
        'locked': !_hasBarbers,
      },
      {
        'label': 'Set Holidays',
        'subtitle': 'Days off',
        'isCompleted': _hasHolidays,
        'onTap': _viewSalonHolidays,
        'icon': Icons.wb_sunny_outlined,
        'locked': !_hasSalon,
      },
    ];

    final nextIdx = steps.indexWhere(
      (s) => !(s['isCompleted'] as bool) && !(s['locked'] as bool? ?? false),
    );
    const pink = Color(0xFFFF6B8B);
    const green = Color(0xFF22C55E);
    final pct = _totalSteps == 0 ? 0.0 : _completedSteps / _totalSteps;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 20.0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: pink,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.rocket_launch_outlined,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Salon Setup',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    Text(
                      '$_completedSteps of $_totalSteps steps complete',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: pct == 1.0
                      ? green.withValues(alpha: 0.12)
                      : pink.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${(pct * 100).round()}%',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: pct == 1.0 ? green : pink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: pct),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOut,
            builder: (context, value, _) => Stack(
              children: [
                Container(
                  height: 7,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: value,
                  child: Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: value >= 1.0 ? green : pink,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              const arrowSlot = 16.0;
              final availableWidth = constraints.maxWidth - (arrowSlot * 4);
              final cardWidth = availableWidth > 0 ? availableWidth / 5 : 60.0;
              return Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(steps.length, (i) {
                  final step = steps[i];
                  final isCompleted = step['isCompleted'] as bool;
                  final isLocked = step['locked'] as bool? ?? false;
                  final isActive = !isCompleted && !isLocked;
                  final isNext = i == nextIdx;
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStepCard(
                        label: step['label'] as String,
                        subtitle: step['subtitle'] as String,
                        icon: step['icon'] as IconData,
                        isCompleted: isCompleted,
                        isLocked: isLocked,
                        isActive: isActive,
                        isNext: isNext,
                        cardWidth: cardWidth,
                        onTap: isActive ? step['onTap'] as VoidCallback? : null,
                      ),
                      if (i < steps.length - 1)
                        SizedBox(
                          width: arrowSlot,
                          child: Center(
                            child: Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 10,
                              color: isCompleted
                                  ? green.withValues(alpha: 0.7)
                                  : const Color(0xFFE0E0E0),
                            ),
                          ),
                        ),
                    ],
                  );
                }),
              );
            },
          ),
          if (_completedSteps > 0 &&
              _completedSteps < _totalSteps &&
              nextIdx >= 0)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: pink,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Up next:  ${steps[nextIdx]['label'] as String}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: pink,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (_completedSteps == _totalSteps)
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutBack,
              builder: (context, v, _) => Transform.scale(
                scale: v,
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 13,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      color: green,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.celebration_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Your salon is ready to launch! 🎉',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepCard({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool isCompleted,
    required bool isLocked,
    required bool isActive,
    required bool isNext,
    required double cardWidth,
    VoidCallback? onTap,
  }) {
    const pink = Color(0xFFFF6B8B);
    const green = Color(0xFF22C55E);
    final Color circleBg = isCompleted
        ? green
        : isActive
        ? pink
        : const Color(0xFFE5E7EB);
    final Color labelColor = isCompleted
        ? const Color(0xFF15803D)
        : isActive
        ? const Color(0xFF1A1A1A)
        : const Color(0xFFB0B5BF);
    final Color subtitleColor = isCompleted
        ? green.withValues(alpha: 0.8)
        : isActive
        ? const Color(0xFF6B7280)
        : const Color(0xFFD1D5DB);

    Widget card = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: cardWidth,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: isCompleted
            ? green.withValues(alpha: 0.06)
            : isNext
            ? pink.withValues(alpha: 0.07)
            : isActive
            ? pink.withValues(alpha: 0.04)
            : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? green.withValues(alpha: 0.4)
              : isNext
              ? pink.withValues(alpha: 0.65)
              : isActive
              ? pink.withValues(alpha: 0.3)
              : const Color(0xFFEEEEEE),
          width: isNext
              ? 1.8
              : isActive
              ? 1.5
              : 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: circleBg, shape: BoxShape.circle),
            child: Center(
              child: isCompleted
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 22,
                    )
                  : isLocked
                  ? const Icon(
                      Icons.lock_outline_rounded,
                      color: Color(0xFFADB5BD),
                      size: 18,
                    )
                  : Icon(icon, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(height: 9),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: labelColor,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: subtitleColor, height: 1.2),
          ),
          const SizedBox(height: 8),
          _buildStatusChip(
            isCompleted: isCompleted,
            isLocked: isLocked,
            isNext: isNext,
          ),
        ],
      ),
    );
    if (isNext) card = ScaleTransition(scale: _pulseAnim, child: card);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }

  Widget _buildStatusChip({
    required bool isCompleted,
    required bool isLocked,
    required bool isNext,
  }) {
    if (isCompleted) {
      return _chip('Done', const Color(0xFF16A34A), const Color(0xFFDCFCE7));
    }
    if (isLocked) {
      return _chip('Locked', const Color(0xFFADB5BD), const Color(0xFFF3F4F6));
    }
    if (isNext) {
      return _chip('Do This', const Color(0xFFFF6B8B), const Color(0xFFFFEDF1));
    }
    return _chip('Pending', const Color(0xFFFF6B8B), const Color(0xFFFFEDF1));
  }

  Widget _chip(String text, Color textColor, Color bgColor) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
    ),
  );

  // ============================================================
  // MANAGEMENT SECTION
  // ============================================================

  Widget _buildManagementSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8.0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.settings, size: 20, color: Color(0xFFFF6B8B)),
              SizedBox(width: 8),
              Text(
                'Management',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Salon Management',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.add_business,
                  label: 'Create Salon',
                  color: const Color(0xFFFF6B8B),
                  onTap: _navigateToCreateSalon,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.edit,
                  label: 'Edit Salon',
                  color: Colors.blue,
                  onTap: _navigateToEditSalon,
                  enabled: _ownerSalons.isNotEmpty,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.beach_access,
                  label: 'Holidays',
                  color: Colors.teal,
                  onTap: _viewSalonHolidays,
                  enabled: _ownerSalons.isNotEmpty,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Service Management',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.build,
                  label: 'Add Service',
                  color: Colors.green,
                  onTap: _navigateToAddService,
                  enabled: _ownerSalons.isNotEmpty,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.list,
                  label: 'Service List',
                  color: Colors.cyan,
                  onTap: _navigateToServiceList,
                  enabled: _ownerSalons.isNotEmpty,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Barber Management',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.person_add,
                  label: 'Add Barber',
                  color: Colors.purple,
                  onTap: _navigateToAddBarber,
                  enabled: _ownerSalons.isNotEmpty,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.calendar_month,
                  label: 'Schedule',
                  color: Colors.teal,
                  onTap: _navigateToBarberSchedule,
                  enabled: _ownerSalons.isNotEmpty,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.beach_access,
                  label: 'Leaves',
                  color: Colors.orange,
                  onTap: _navigateToBarberLeaves,
                  enabled: _ownerSalons.isNotEmpty,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.list,
                  label: 'Barber List',
                  color: Colors.indigo,
                  onTap: _navigateToBarberList,
                  enabled: _ownerSalons.isNotEmpty,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Offers & Promotions',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.local_offer,
                  label: 'Manage Offers',
                  color: const Color(0xFFFF6B8B),
                  onTap: _navigateToOffers,
                  enabled: _ownerSalons.isNotEmpty,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Reports',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.bar_chart,
                  label: 'Reports',
                  color: Colors.deepOrange,
                  onTap: _viewReports,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.analytics,
                  label: 'Analytics',
                  color: Colors.indigoAccent,
                  onTap: _viewAnalytics,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildQuickAction(
                  icon: Icons.settings,
                  label: 'Settings',
                  color: Colors.grey,
                  onTap: _viewSettings,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: enabled
              ? color.withValues(alpha: 0.1)
              : Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: enabled ? color : Colors.grey[400], size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: enabled ? color : Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalonSelector() {
    if (_ownerSalons.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8.0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.store, size: 18, color: Color(0xFFFF6B8B)),
          const SizedBox(width: 8),
          const Text(
            'Salon:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _ownerSalons.map((salon) {
                  final isSelected = _selectedSalonId == salon['id'].toString();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        salon['name'] ?? 'Salon',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                      selected: isSelected,
                      onSelected: (_) => _switchSalon(salon['id'].toString()),
                      backgroundColor: Colors.grey[100],
                      selectedColor: const Color(
                        0xFFFF6B8B,
                      ).withValues(alpha: 0.2),
                      checkmarkColor: const Color(0xFFFF6B8B),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        color: isSelected
                            ? const Color(0xFFFF6B8B)
                            : Colors.grey[800],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: _navigateToEditSalon,
            tooltip: 'Edit Salon',
            color: const Color(0xFFFF6B8B),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SIMPLE HEADER
  // ============================================================

  Widget _buildSimpleHeader() {
    final isWeb = MediaQuery.of(context).size.width > 800;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: isWeb
          ? Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
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
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: _changeTimezone,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF6B8B,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentTimezoneFlag,
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _currentTimezone
                                      .split('/')
                                      .last
                                      .replaceAll('_', ' '),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFFFF6B8B),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _currentTimezoneOffset,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                              const Icon(
                                Icons.arrow_drop_down,
                                size: 16,
                                color: Color(0xFFFF6B8B),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _currentDate,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 12,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _currentDate,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: _changeTimezone,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B8B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _currentTimezoneFlag,
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _currentTimezone
                                  .split('/')
                                  .last
                                  .replaceAll('_', ' '),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFFFF6B8B),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            size: 14,
                            color: Color(0xFFFF6B8B),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // ============================================================
  // NAVIGATION METHODS
  // ============================================================

  void _navigateToCreateSalon() async {
    final result = await context.push('/owner/salon/create');
    if (result == true) await _refreshAllData();
  }

  void _navigateToEditSalon() async {
    if (_ownerSalons.isEmpty) {
      _showCreateSalonFirstDialog();
      return;
    }
    final result = await context.push(
      '/owner/salon/edit?salonId=$_selectedSalonId',
    );
    if (result == true) await _refreshAllData();
  }

  void _showSalonSelectionDialogForServices() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Salon'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _ownerSalons.length,
            itemBuilder: (context, index) {
              final salon = _ownerSalons[index];
              return ListTile(
                leading: const Icon(Icons.store, color: Color(0xFFFF6B8B)),
                title: Text(
                  salon['name'] ?? 'Salon',
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.pop(context);
                  context.push(
                    '/owner/services?salonId=${salon['id']}&salonName=${Uri.encodeComponent(salon['name'] ?? 'Salon')}',
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _viewReports() => context.push('/owner/reports');
  void _viewAnalytics() => context.push('/owner/analytics');
  void _viewSettings() => context.push('/owner/settings');

  void _showCreateSalonFirstDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Salon First'),
        content: const Text(
          'You need to create a salon before managing barbers or services.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToCreateSalon();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Create Salon'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // NOTIFICATION LISTENERS
  // ============================================================

  void _setupNotificationListeners() {
    try {
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (message.data['type'] == 'new_booking') {
          _showNewBookingAlert(message);
          setState(() {
            _pendingBookings++;
            pendingAppointments++;
          });
        }
      });
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (message.data['type'] == 'new_booking') _viewBookings();
      });
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _showNewBookingAlert(RemoteMessage message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Booking!'),
        content: Text(
          message.notification?.body ?? 'A customer has booked an appointment',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _viewBookings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B8B),
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 36),
            ),
            child: const Text('View'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DRAWER & LOGOUT
  // ============================================================

  void _openDrawer() {
    try {
      if (_scaffoldKey.currentState != null) {
        _scaffoldKey.currentState!.openDrawer();
      } else {
        Scaffold.of(context).openDrawer();
      }
    } catch (e) {
      _showMenuDialog();
    }
  }

  void _showMenuDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Menu'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.dashboard),
                title: const Text('Dashboard'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: const Text('Appointments'),
                onTap: () {
                  Navigator.pop(context);
                  _viewBookings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.people),
                title: const Text('Customers'),
                onTap: () {
                  Navigator.pop(context);
                  _viewAllCustomers();
                },
              ),
              ListTile(
                leading: const Icon(Icons.content_cut),
                title: const Text('Barbers'),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToBarberList();
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_offer),
                title: const Text('Offers'),
                onTap: () {
                  Navigator.pop(context);
                  _navigateToOffers();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Logout'),
                onTap: () {
                  Navigator.pop(context);
                  _logout(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    showLogoutConfirmation(
      context,
      onLogoutConfirmed: () async {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
          ),
        );
        try {
          await SessionManager.logoutForContinue();
          await appState.refreshState();
          if (context.mounted) {
            Navigator.pop(context);
            context.go('/');
          }
        } catch (e) {
          if (context.mounted) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Logout failed: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          isWeb ? 'Owner Dashboard' : 'Dashboard',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFFFF6B8B),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: isWeb,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: _openDrawer,
          tooltip: 'Menu',
        ),
      ),
      drawer: SideMenu(
        userRole: 'owner',
        userName: _userName,
        userEmail: _userEmail,
        profileImageUrl: _profileImageUrl,
        selectedSalonId: _selectedSalonId,
        onMenuItemSelected: () => _refreshAllData(),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF6B8B)),
            )
          : RefreshIndicator(
              onRefresh: _refreshAllData,
              color: const Color(0xFFFF6B8B),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ✅ PERMISSION CARD - Updated with contextual support
                    if (_showPermissionCard && !_hasPermission)
                      PermissionCard(
                        onEnable: () => _enableNotifications(action: null),
                        onNotNow: _handleNotNow,
                        title: _permissionManager.getPermissionCardTitle(),
                        message: _permissionManager.getPermissionCardMessage(),
                        compact: true,
                      ),
                    _buildSimpleHeader(),
                    if (_completedSteps < _totalSteps) _buildStepFlow(),
                    if (_ownerSalons.length > 1) _buildSalonSelector(),
                    if (_ownerSalons.isEmpty)
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.warning,
                              color: Colors.orange,
                              size: 40,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'No Salons Found',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Create your first salon to get started',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _navigateToCreateSalon,
                              icon: const Icon(Icons.add_business, size: 18),
                              label: const Text('Create Salon'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6B8B),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_ownerSalons.isNotEmpty)
                      _isSwitchingSalon
                          ? const Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFFFF6B8B),
                                ),
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Expanded(
                                        child: DashboardStatCard(
                                          title: "Today's Appointments",
                                          value: '$_todayAppointments',
                                          icon: Icons.calendar_today,
                                          color: Colors.blue,
                                          onTap: _viewBookings,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DashboardStatCard(
                                          title: 'Pending',
                                          value: '$_pendingBookings',
                                          icon: Icons.pending_actions,
                                          color: Colors.orange,
                                          onTap: _viewBookings,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Expanded(
                                        child: DashboardStatCard(
                                          title: 'Customers',
                                          value: '$_totalCustomers',
                                          icon: Icons.people,
                                          color: Colors.purple,
                                          onTap: _viewAllCustomers,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DashboardStatCard(
                                          title: 'Barbers',
                                          value: '$_activeBarbers',
                                          icon: Icons.content_cut,
                                          color: Colors.green,
                                          onTap: _navigateToBarberList,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                  ),
                                  child: DashboardStatCard(
                                    title: 'Revenue',
                                    value: 'Rs. $_totalRevenue',
                                    icon: Icons.currency_rupee,
                                    color: Colors.green,
                                    fullWidth: true,
                                    onTap: _viewRevenue,
                                  ),
                                ),
                              ],
                            ),
                    const SizedBox(height: 16),
                    _buildManagementSection(),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
    );
  }
}