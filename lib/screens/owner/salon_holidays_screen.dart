import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../alertBox/show_custom_alert.dart';
import '../../services/timezone_service.dart';
import '../../extensions/context_extensions.dart';
import '../../theme/app_theme.dart';

class SalonHolidaysScreen extends StatefulWidget {
  final int salonId;
  final String salonName;

  const SalonHolidaysScreen({
    super.key,
    required this.salonId,
    required this.salonName,
  });

  @override
  State<SalonHolidaysScreen> createState() => _SalonHolidaysScreenState();
}

class _SalonHolidaysScreenState extends State<SalonHolidaysScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _holidays = [];
  bool _isLoading = true;
  bool _isDeleting = false;
  final Set<int> _selectedForDelete = {};
  bool _isSelectMode = false;

  // Timezone variables
  String _userTimezone = '';
  String _salonTimezone = '';
  bool _isTimezoneLoaded = false;

  // ✅ Web Scroll Controller
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeWithTimezone();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ==================== CORRECT TIMEZONE FUNCTIONS ====================

  Future<void> _initializeWithTimezone() async {
    await TimezoneService.initialize();

    final prefs = await SharedPreferences.getInstance();

    _userTimezone =
        prefs.getString('user_timezone') ??
        TimezoneService.getCurrentTimezone();

    await _loadSalonTimezone();

    setState(() {
      _isTimezoneLoaded = true;
    });

    await _loadHolidays();
  }

  Future<void> _loadSalonTimezone() async {
    try {
      final response = await supabase
          .from('salons')
          .select('timezone')
          .eq('id', widget.salonId)
          .single();

      _salonTimezone =
          response['timezone'] ?? TimezoneService.getCurrentTimezone();
    } catch (e) {
      debugPrint('❌ Error loading salon timezone: $e');
      _salonTimezone = TimezoneService.getCurrentTimezone();
    }
  }

  DateTime _utcToLocalDate(String utcDateStr) {
    try {
      final utcDateTime = DateTime.parse(utcDateStr);
      final localDateTime = TimezoneService.utcToLocalDateTimeForDate(
        '12:00:00',
        utcDateTime,
      );
      return DateTime(
        localDateTime.year,
        localDateTime.month,
        localDateTime.day,
      );
    } catch (e) {
      debugPrint('❌ Error converting UTC to local: $e');
      final utcDateTime = DateTime.parse(utcDateStr);
      return DateTime(utcDateTime.year, utcDateTime.month, utcDateTime.day);
    }
  }

  String _formatDateForDisplay(String utcDateStr) {
    try {
      final localDate = _utcToLocalDate(utcDateStr);
      return DateFormat('EEEE, MMM d, yyyy').format(localDate);
    } catch (e) {
      debugPrint('❌ Error formatting date: $e');
      return utcDateStr;
    }
  }

  bool _isPastHoliday(String utcDateStr) {
    try {
      final localDate = _utcToLocalDate(utcDateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return localDate.isBefore(today);
    } catch (e) {
      debugPrint('❌ Error checking past holiday: $e');
      return false;
    }
  }

  String _getTimezoneDisplay() {
    return '${TimezoneService.getCurrentFlag()} ${TimezoneService.getTimezoneDisplayName()} (${TimezoneService.getUtcOffsetString()})';
  }

  // ==================== LOAD HOLIDAYS ====================

  Future<void> _loadHolidays() async {
    if (!_isTimezoneLoaded) return;

    setState(() => _isLoading = true);

    try {
      final response = await supabase
          .from('salon_holidays')
          .select()
          .eq('salon_id', widget.salonId)
          .order('holiday_date', ascending: false);

      setState(() {
        _holidays = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });

      debugPrint('✅ Loaded ${_holidays.length} holidays');
    } catch (e) {
      debugPrint('❌ Error loading holidays: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        _showSnackBar('Error loading holidays', Colors.red);
      }
    }
  }

  // ==================== ADD HOLIDAY ====================

  Future<void> _addHoliday() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddEditHolidayDialog(
        salonId: widget.salonId,
        salonTimezone: _salonTimezone,
        userTimezone: _userTimezone,
      ),
    );

    if (result != null && result['success'] == true) {
      _loadHolidays();
      _showSnackBar('Holiday added successfully', Colors.green);
    }
  }

  // ==================== EDIT HOLIDAY ====================

  Future<void> _editHoliday(Map<String, dynamic> holiday) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _AddEditHolidayDialog(
        salonId: widget.salonId,
        holidayToEdit: holiday,
        salonTimezone: _salonTimezone,
        userTimezone: _userTimezone,
      ),
    );

    if (result != null && result['success'] == true) {
      _loadHolidays();
      _showSnackBar('Holiday updated successfully', Colors.green);
    }
  }

  // ==================== DELETE SELECTED HOLIDAYS ====================

  Future<void> _deleteSelectedHolidays() async {
    if (_selectedForDelete.isEmpty) return;

    final confirm = await showCustomAlert(
      context: context,
      title: "Delete Holidays",
      message:
          "Are you sure you want to delete ${_selectedForDelete.length} selected holiday(s)?",
      isError: true,
      showCancelButton: true,
    );

    if (confirm == true) {
      setState(() => _isDeleting = true);

      try {
        for (int id in _selectedForDelete) {
          await supabase.from('salon_holidays').delete().eq('id', id);
        }

        _loadHolidays();
        setState(() {
          _selectedForDelete.clear();
          _isSelectMode = false;
          _isDeleting = false;
        });
        _showSnackBar('Holidays deleted successfully', Colors.green);
      } catch (e) {
        debugPrint('❌ Error deleting holidays: $e');
        _showSnackBar('Error deleting holidays', Colors.red);
        setState(() => _isDeleting = false);
      }
    }
  }

  // ==================== DELETE SINGLE HOLIDAY ====================

  Future<void> _deleteHoliday(Map<String, dynamic> holiday) async {
    final confirm = await showCustomAlert(
      context: context,
      title: "Delete Holiday",
      message: "Are you sure you want to delete '${holiday['name']}'?",
      isError: true,
      showCancelButton: true,
    );

    if (confirm == true) {
      try {
        await supabase.from('salon_holidays').delete().eq('id', holiday['id']);

        _loadHolidays();
        _showSnackBar('Holiday deleted successfully', Colors.green);
      } catch (e) {
        _showSnackBar('Error deleting holiday', Colors.red);
      }
    }
  }

  // ==================== SELECTION METHODS ====================

  void _toggleSelectMode() {
    setState(() {
      _isSelectMode = !_isSelectMode;
      if (!_isSelectMode) {
        _selectedForDelete.clear();
      }
    });
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedForDelete.contains(id)) {
        _selectedForDelete.remove(id);
      } else {
        _selectedForDelete.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selectedForDelete.clear();
      for (var holiday in _holidays) {
        _selectedForDelete.add(holiday['id'] as int);
      }
    });
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ==================== UI BUILDERS ====================

  @override
  Widget build(BuildContext context) {
    final isWeb = context.isWeb;
    final isDark = context.isDarkMode;

    if (!_isTimezoneLoaded) {
      return Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        appBar: AppBar(
          title: Text('Holidays - ${widget.salonName}'),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(),
              ),
              SizedBox(height: 16),
              Text('Loading timezone...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
      appBar: AppBar(
        title: Text(
          'Holidays - ${widget.salonName}',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        centerTitle: isWeb,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        actions: [
          if (!_isLoading && _holidays.isNotEmpty)
            IconButton(
              icon: Icon(
                _isSelectMode ? Icons.close : Icons.edit,
                color: Colors.white,
              ),
              onPressed: _toggleSelectMode,
              tooltip: _isSelectMode ? 'Cancel' : 'Select Items',
            ),
          if (_isSelectMode)
            IconButton(
              icon: const Icon(Icons.select_all, color: Colors.white),
              onPressed: _selectAll,
              tooltip: 'Select All',
            ),
          if (_isSelectMode && _selectedForDelete.isNotEmpty)
            IconButton(
              icon: _isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.delete, color: Colors.red),
              onPressed: _isDeleting ? null : _deleteSelectedHolidays,
              tooltip: 'Delete Selected',
            ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _addHoliday,
            tooltip: 'Add Holiday',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadHolidays,
            tooltip: 'Refresh',
          ),
        ],
      ),
      // ✅ EDGE-TO-EDGE: SafeArea with Web/Mobile layouts
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : _holidays.isEmpty
            ? _buildEmptyState(isWeb)
            : isWeb
            ? _buildWebLayout()
            : _buildMobileLayout(),
      ),
    );
  }

  // ✅ WEB LAYOUT - Centered with Scrollbar
  Widget _buildWebLayout() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          thickness: 8.0,
          radius: const Radius.circular(10),
          scrollbarOrientation: ScrollbarOrientation.right,
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: _buildContent(),
          ),
        ),
      ),
    );
  }

  // ✅ MOBILE LAYOUT
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      child: _buildContent(),
    );
  }

  // ✅ CONTENT
  Widget _buildContent() {
    final isDark = context.isDarkMode;
    final isWeb = context.isWeb;

    final upcomingCount = _holidays
        .where((h) => !_isPastHoliday(h['holiday_date']))
        .length;
    final pastCount = _holidays
        .where((h) => _isPastHoliday(h['holiday_date']))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timezone Info Card
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.blue.withValues(alpha: 0.15)
                : Colors.blue[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.blue.withValues(alpha: 0.3)
                  : Colors.blue[200]!,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.access_time,
                size: 20,
                color: isDark ? Colors.blue[300] : Colors.blue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '🌍 Your Timezone: ${_getTimezoneDisplay()}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.blue[300] : Colors.blueGrey,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Stats Row
        if (isWeb)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: isDark ? Border.all(color: Colors.grey[800]!) : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                _buildStatCard(
                  'Total Holidays',
                  _holidays.length.toString(),
                  Icons.event,
                  AppTheme.primary,
                  isDark,
                ),
                _buildStatCard(
                  'Upcoming',
                  upcomingCount.toString(),
                  Icons.upcoming,
                  Colors.green,
                  isDark,
                ),
                _buildStatCard(
                  'Past',
                  pastCount.toString(),
                  Icons.history,
                  Colors.grey,
                  isDark,
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0),
            child: Row(
              children: [
                _buildMobileStatCard(
                  'Total',
                  _holidays.length.toString(),
                  Icons.event,
                  AppTheme.primary,
                  isDark,
                ),
                const SizedBox(width: 8),
                _buildMobileStatCard(
                  'Upcoming',
                  upcomingCount.toString(),
                  Icons.upcoming,
                  Colors.green,
                  isDark,
                ),
                const SizedBox(width: 8),
                _buildMobileStatCard(
                  'Past',
                  pastCount.toString(),
                  Icons.history,
                  Colors.grey,
                  isDark,
                ),
              ],
            ),
          ),

        const SizedBox(height: 16),

        // Holidays List
        if (isWeb) _buildWebHolidaysList() else _buildMobileHolidaysList(),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : color,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : color,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ WEB HOLIDAYS LIST - Table View
  Widget _buildWebHolidaysList() {
    final isDark = context.isDarkMode;

    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? AppTheme.primary.withValues(alpha: 0.15)
                : AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              if (_isSelectMode) const SizedBox(width: 50),
              Expanded(
                flex: 2,
                child: Text(
                  'Date',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'Holiday Name',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'Description',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  'Recurring',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                flex: 1,
                child: Text(
                  'Actions',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Holidays Rows
        ..._holidays.map((holiday) {
          final isSelected = _selectedForDelete.contains(holiday['id']);
          final isPast = _isPastHoliday(holiday['holiday_date']);

          return Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.red.withValues(alpha: 0.05)
                  : isPast
                  ? (isDark
                        ? Colors.grey[800]
                        : Colors.grey.withValues(alpha: 0.05))
                  : (isDark ? const Color(0xFF1E1E1E) : Colors.white),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? Colors.red
                    : (isDark ? Colors.grey[700]! : Colors.grey[200]!),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                if (_isSelectMode)
                  SizedBox(
                    width: 50,
                    child: Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleSelection(holiday['id']),
                      activeColor: AppTheme.primary,
                    ),
                  ),
                Expanded(
                  flex: 2,
                  child: Text(
                    _formatDateForDisplay(holiday['holiday_date']),
                    style: TextStyle(
                      color: isPast
                          ? (isDark ? Colors.white70 : Colors.grey[600])
                          : (isDark ? Colors.white : Colors.black),
                      decoration: isPast ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    holiday['name'],
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: isPast
                          ? (isDark ? Colors.white70 : Colors.grey[600])
                          : (isDark ? Colors.white : Colors.black),
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    holiday['description'] ?? '-',
                    style: TextStyle(
                      color: isPast
                          ? (isDark ? Colors.white30 : Colors.grey[500])
                          : (isDark ? Colors.white60 : Colors.grey[700]),
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Center(
                    child: holiday['is_recurring'] == true
                        ? Icon(
                            Icons.repeat,
                            color: isDark ? Colors.orange[300] : Colors.orange,
                            size: 20,
                          )
                        : Icon(
                            Icons.event,
                            color: isDark ? Colors.white30 : Colors.grey,
                            size: 20,
                          ),
                  ),
                ),
                Expanded(
                  flex: 1,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.edit,
                          color: isDark ? Colors.blue[300] : Colors.blue,
                          size: 20,
                        ),
                        onPressed: () => _editHoliday(holiday),
                        tooltip: 'Edit',
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete,
                          color: isDark ? Colors.red[300] : Colors.red,
                          size: 20,
                        ),
                        onPressed: () => _deleteHoliday(holiday),
                        tooltip: 'Delete',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ✅ MOBILE HOLIDAYS LIST - Card View
  Widget _buildMobileHolidaysList() {
    final isDark = context.isDarkMode;

    return Column(
      children: _holidays.map(
        (holiday) {
          final isPast = _isPastHoliday(holiday['holiday_date']);
          final isSelected = _selectedForDelete.contains(holiday['id']);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: isDark
                ? (isSelected
                      ? Colors.red.withValues(alpha: 0.15)
                      : const Color(0xFF1E1E1E))
                : (isSelected
                      ? Colors.red.withValues(alpha: 0.05)
                      : Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isSelected
                  ? BorderSide(color: Colors.red, width: 1.5)
                  : BorderSide.none,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  leading: CircleAvatar(
                    backgroundColor: isPast
                        ? (isDark ? Colors.grey[700] : Colors.grey[300])
                        : AppTheme.primary.withValues(alpha: 0.1),
                    child: Icon(
                      holiday['is_recurring'] == true
                          ? Icons.repeat
                          : Icons.event,
                      color: isPast
                          ? (isDark ? Colors.white30 : Colors.grey)
                          : AppTheme.primary,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    holiday['name'],
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      decoration: isPast ? TextDecoration.lineThrough : null,
                      color: isPast
                          ? (isDark ? Colors.white70 : Colors.grey[600])
                          : (isDark ? Colors.white : Colors.black),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        _formatDateForDisplay(holiday['holiday_date']),
                        style: TextStyle(
                          fontSize: 12,
                          color: isPast
                              ? (isDark ? Colors.white30 : Colors.grey[500])
                              : (isDark ? Colors.white60 : Colors.grey[700]),
                        ),
                      ),
                      if (holiday['description'] != null &&
                          holiday['description'].toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          holiday['description'],
                          style: TextStyle(
                            fontSize: 11,
                            color: isPast
                                ? (isDark ? Colors.white30 : Colors.grey[500])
                                : (isDark ? Colors.white60 : Colors.grey[600]),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.edit,
                          color: isDark ? Colors.blue[300] : Colors.blue,
                          size: 20,
                        ),
                        onPressed: () => _editHoliday(holiday),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(
                          Icons.delete,
                          color: isDark ? Colors.red[300] : Colors.red,
                          size: 20,
                        ),
                        onPressed: () => _deleteHoliday(holiday),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                if (_isSelectMode)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[50],
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleSelection(holiday['id']),
                          activeColor: AppTheme.primary,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        Text(
                          'Select for deletion',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ).toList(), // ✅ ඉතිරි වෙනවා - මෙය Column එකේ children එකට යන නිසා toList() අවශ්‍යයි
    );
  }

  Widget _buildEmptyState(bool isWeb) {
    final isDark = context.isDarkMode;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.beach_access,
            size: isWeb ? 80 : 64,
            color: isDark ? Colors.white30 : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No holidays added yet',
            style: TextStyle(
              fontSize: 18,
              color: isDark ? Colors.white60 : Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add holidays to mark days when salon is closed',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addHoliday,
            icon: const Icon(Icons.add),
            label: const Text('Add Holiday'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== ADD/EDIT HOLIDAY DIALOG ====================

class _AddEditHolidayDialog extends StatefulWidget {
  final int salonId;
  final Map<String, dynamic>? holidayToEdit;
  final String salonTimezone;
  final String userTimezone;

  const _AddEditHolidayDialog({
    required this.salonId,
    this.holidayToEdit,
    required this.salonTimezone,
    required this.userTimezone,
  });

  @override
  State<_AddEditHolidayDialog> createState() => _AddEditHolidayDialogState();
}

class _AddEditHolidayDialogState extends State<_AddEditHolidayDialog> {
  final supabase = Supabase.instance.client;

  DateTime? _selectedLocalDate;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isRecurring = false;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isEditMode = false;
  int _editId = 0;

  @override
  void initState() {
    super.initState();
    if (widget.holidayToEdit != null) {
      _isEditMode = true;
      _loadHolidayData();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  DateTime _utcToLocalDate(String utcDateStr) {
    try {
      final utcDateTime = DateTime.parse(utcDateStr);
      final localDateTime = TimezoneService.utcToLocalDateTimeForDate(
        '12:00:00',
        utcDateTime,
      );
      return DateTime(
        localDateTime.year,
        localDateTime.month,
        localDateTime.day,
      );
    } catch (e) {
      debugPrint('Error converting UTC to local: $e');
      final utcDateTime = DateTime.parse(utcDateStr);
      return DateTime(utcDateTime.year, utcDateTime.month, utcDateTime.day);
    }
  }

  String _localDateToUtcDateString(DateTime localDate) {
    try {
      final utcDateTime = DateTime.utc(
        localDate.year,
        localDate.month,
        localDate.day,
      );
      return '${utcDateTime.year.toString().padLeft(4, '0')}-${utcDateTime.month.toString().padLeft(2, '0')}-${utcDateTime.day.toString().padLeft(2, '0')}';
    } catch (e) {
      debugPrint('Error converting local date to UTC: $e');
      return '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
    }
  }

  void _loadHolidayData() {
    final holiday = widget.holidayToEdit!;
    _editId = holiday['id'] as int;
    _selectedLocalDate = _utcToLocalDate(holiday['holiday_date']);
    _nameController.text = holiday['name'] ?? '';
    _descriptionController.text = holiday['description'] ?? '';
    _isRecurring = holiday['is_recurring'] ?? false;

    debugPrint(
      '📅 Loading holiday - UTC: ${holiday['holiday_date']} → Local: ${DateFormat('yyyy-MM-dd').format(_selectedLocalDate!)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final isWeb = context.isWeb;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Container(
        width: isWeb ? 500 : double.infinity,
        constraints: BoxConstraints(
          maxWidth: isWeb ? 500 : MediaQuery.of(context).size.width * 0.95,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _isEditMode ? Icons.edit : Icons.add,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isEditMode ? 'Edit Holiday' : 'Add Holiday',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Timezone info
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.blue.withValues(alpha: 0.15)
                            : Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
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
                              'Your Timezone: ${TimezoneService.getTimezoneDisplayName()}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? Colors.blue[300]
                                    : Colors.blueGrey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.red.withValues(alpha: 0.15)
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isDark
                                ? Colors.red.withValues(alpha: 0.3)
                                : Colors.red.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: isDark
                                  ? Colors.red[300]
                                  : Colors.red.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.red[300]
                                      : Colors.red.shade700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    const Text(
                      'Holiday Name *',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameController,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g., New Year, Poya Day, Special Holiday',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey[500],
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[300]!,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[300]!,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppTheme.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        fillColor: isDark
                            ? const Color(0xFF2A2A2A)
                            : Colors.white,
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Date *',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () async {
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);

                        final date = await showDatePicker(
                          context: context,
                          initialDate: _selectedLocalDate ?? today,
                          firstDate: today,
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date != null) {
                          setState(() {
                            _selectedLocalDate = date;
                            _errorMessage = null;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[300]!,
                          ),
                          borderRadius: BorderRadius.circular(8),
                          color: isDark
                              ? const Color(0xFF2A2A2A)
                              : Colors.white,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 16,
                              color: isDark ? Colors.white60 : Colors.grey[600],
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _selectedLocalDate != null
                                    ? DateFormat(
                                        'EEEE, MMM d, yyyy',
                                      ).format(_selectedLocalDate!)
                                    : 'Select date',
                                style: TextStyle(
                                  color: _selectedLocalDate != null
                                      ? (isDark ? Colors.white : Colors.black)
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.grey[500]),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'Description',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Optional description',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey[500],
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[300]!,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                            color: isDark
                                ? Colors.grey[700]!
                                : Colors.grey[300]!,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: AppTheme.primary,
                            width: 2,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        fillColor: isDark
                            ? const Color(0xFF2A2A2A)
                            : Colors.white,
                        filled: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Checkbox(
                          value: _isRecurring,
                          onChanged: (value) {
                            setState(() {
                              _isRecurring = value ?? false;
                            });
                          },
                          activeColor: AppTheme.primary,
                          checkColor: Colors.white,
                        ),
                        Text(
                          'Recurring (repeats every year)',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.grey[600],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _saveHoliday,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(_isEditMode ? 'Update' : 'Save'),
                        ),
                      ],
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

  Future<void> _saveHoliday() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a holiday name';
      });
      return;
    }

    if (_selectedLocalDate == null) {
      setState(() {
        _errorMessage = 'Please select a date';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final utcDateStr = _localDateToUtcDateString(_selectedLocalDate!);

      debugPrint(
        '📅 Saving holiday - Local: ${DateFormat('yyyy-MM-dd').format(_selectedLocalDate!)} → UTC: $utcDateStr',
      );

      final holidayData = {
        'salon_id': widget.salonId,
        'holiday_date': utcDateStr,
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'is_recurring': _isRecurring,
      };

      if (_isEditMode) {
        await supabase
            .from('salon_holidays')
            .update(holidayData)
            .eq('id', _editId);
      } else {
        final existing = await supabase
            .from('salon_holidays')
            .select()
            .eq('salon_id', widget.salonId)
            .eq('holiday_date', utcDateStr)
            .maybeSingle();

        if (existing != null) {
          setState(() {
            _errorMessage = 'A holiday already exists on this date';
            _isLoading = false;
          });
          return;
        }

        holidayData['created_by'] = supabase.auth.currentUser?.id;
        await supabase.from('salon_holidays').insert(holidayData);
      }

      if (mounted) {
        Navigator.pop(context, {'success': true});
      }
    } catch (e) {
      debugPrint('❌ Error saving holiday: $e');
      setState(() {
        _errorMessage = 'Error saving holiday: ${e.toString()}';
        _isLoading = false;
      });
    }
  }
}
