import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/currency_service.dart';
import 'package:flutter_application_1/services/currency_settings_service.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class CurrencySettingsScreen extends StatefulWidget {
  const CurrencySettingsScreen({super.key});

  @override
  State<CurrencySettingsScreen> createState() => _CurrencySettingsScreenState();
}

class _CurrencySettingsScreenState extends State<CurrencySettingsScreen> {
  final _currencyService = CurrencyService.instance;
  final _currencySettings = CurrencySettingsService.instance;

  String _currentCurrency = 'LKR';
  String _initialCurrency = 'LKR'; // ✅ NEW: track initial value
  bool _hasChanged = false;        // ✅ NEW: track actual changes
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrency();
  }

  // ============================================================
  // ✅ Load current currency from DB
  // ============================================================
  Future<void> _loadCurrency() async {
    setState(() => _isLoading = true);

    final currency = await _currencySettings.getUserCurrency();
    if (!mounted) return;

    setState(() {
      _currentCurrency = currency;
      _initialCurrency = currency; // ✅ Store initial
      _hasChanged = false;          // ✅ No change yet
      _isLoading = false;
    });
  }

  // ============================================================
  // ✅ Save currency change
  // ============================================================
  Future<void> _saveCurrency(String currency) async {
    if (currency == _currentCurrency) return;

    setState(() => _isSaving = true);

    final success = await _currencySettings.updateUserCurrency(currency);
    if (!mounted) return;

    setState(() {
      _isSaving = false;
      if (success) {
        _currentCurrency = currency;
        // ✅ Only mark changed if different from initial
        _hasChanged = (_currentCurrency != _initialCurrency);
      }
    });

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Preferred currency: $currency'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update currency'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ============================================================
  // ✅ Handle back navigation — return _hasChanged
  // ============================================================
  void _handleBack() {
    Navigator.pop(context, _hasChanged);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // ✅ Return true ONLY if currency was actually changed
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : Colors.white,
        appBar: AppBar(
          title: const Text(
            'Preferred Currency',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: _handleBack,
            tooltip: 'Back',
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.primary),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // =====================================================
                  // INFO CARD
                  // =====================================================
                  Card(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.grey[50],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppTheme.primary,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'About Currency Display',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Salon prices are always charged in the '
                                  'salon\'s local currency. This setting only '
                                  'affects how prices are displayed to you.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.4,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // =====================================================
                  // SECTION HEADER
                  // =====================================================
                  Text(
                    'SELECT YOUR CURRENCY',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      color: isDark ? Colors.white60 : Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // =====================================================
                  // CURRENCY LIST
                  // =====================================================
                  ...CurrencySettingsService.supportedCurrencies.map((code) {
                    final info = _currencyService.getInfo(code);
                    final isSelected = code == _currentCurrency;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _isSaving
                              ? null
                              : () => _saveCurrency(code),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.primary.withValues(alpha: 0.08)
                                  : (isDark
                                      ? const Color(0xFF1E1E1E)
                                      : Colors.white),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primary
                                    : (isDark
                                        ? Colors.grey[800]!
                                        : Colors.grey[200]!),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      info.symbol,
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        info.name,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: isSelected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${info.code} · ${info.symbol}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white60
                                              : Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check_circle,
                                    color: AppTheme.primary,
                                  )
                                else
                                  Icon(
                                    Icons.circle_outlined,
                                    color: isDark
                                        ? Colors.grey[700]
                                        : Colors.grey[300],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                  // =====================================================
                  // INFO BANNER (only if changed)
                  // =====================================================
                  if (_hasChanged) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.green.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: Colors.green[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Currency will update on your dashboard when you return.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
      ),
    );
  }
}