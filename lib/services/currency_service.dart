import 'package:flutter/material.dart';

class CurrencyService {
  // Private constructor - singleton pattern
  CurrencyService._();
  static final CurrencyService instance = CurrencyService._();

  // ============================================
  // SUPPORTED CURRENCIES MAP
  // ============================================
  static const Map<String, CurrencyInfo> _currencies = {
    'LKR': CurrencyInfo(
      code: 'LKR',
      symbol: 'Rs.',
      name: 'Sri Lankan Rupee',
      icon: Icons.currency_rupee,
      decimals: 0,
      hint: 'e.g., 1500',
    ),
    'USD': CurrencyInfo(
      code: 'USD',
      symbol: '\$',
      name: 'US Dollar',
      icon: Icons.attach_money,
      decimals: 2,
      hint: 'e.g., 15.00',
    ),
    'INR': CurrencyInfo(
      code: 'INR',
      symbol: '₹',
      name: 'Indian Rupee',
      icon: Icons.currency_rupee,
      decimals: 0,
      hint: 'e.g., 800',
    ),
    'GBP': CurrencyInfo(
      code: 'GBP',
      symbol: '£',
      name: 'British Pound',
      icon: Icons.currency_pound,
      decimals: 2,
      hint: 'e.g., 12.00',
    ),
    'EUR': CurrencyInfo(
      code: 'EUR',
      symbol: '€',
      name: 'Euro',
      icon: Icons.euro,
      decimals: 2,
      hint: 'e.g., 14.00',
    ),
    'AUD': CurrencyInfo(
      code: 'AUD',
      symbol: 'A\$',
      name: 'Australian Dollar',
      icon: Icons.attach_money,
      decimals: 2,
      hint: 'e.g., 22.00',
    ),
    'CAD': CurrencyInfo(
      code: 'CAD',
      symbol: 'C\$',
      name: 'Canadian Dollar',
      icon: Icons.attach_money,
      decimals: 2,
      hint: 'e.g., 20.00',
    ),
    'SGD': CurrencyInfo(
      code: 'SGD',
      symbol: 'S\$',
      name: 'Singapore Dollar',
      icon: Icons.attach_money,
      decimals: 2,
      hint: 'e.g., 20.00',
    ),
    'AED': CurrencyInfo(
      code: 'AED',
      symbol: 'د.إ',
      name: 'UAE Dirham',
      icon: Icons.attach_money,
      decimals: 2,
      hint: 'e.g., 55.00',
    ),
    'JPY': CurrencyInfo(
      code: 'JPY',
      symbol: '¥',
      name: 'Japanese Yen',
      icon: Icons.currency_yen,
      decimals: 0,
      hint: 'e.g., 1500',
    ),
    'CNY': CurrencyInfo(
      code: 'CNY',
      symbol: '¥',
      name: 'Chinese Yuan',
      icon: Icons.currency_yen,
      decimals: 2,
      hint: 'e.g., 70.00',
    ),
    'NZD': CurrencyInfo(
      code: 'NZD',
      symbol: 'NZ\$',
      name: 'New Zealand Dollar',
      icon: Icons.attach_money,
      decimals: 2,
      hint: 'e.g., 24.00',
    ),
    'CHF': CurrencyInfo(
      code: 'CHF',
      symbol: 'CHF',
      name: 'Swiss Franc',
      icon: Icons.attach_money,
      decimals: 2,
      hint: 'e.g., 13.00',
    ),
    'MYR': CurrencyInfo(
      code: 'MYR',
      symbol: 'RM',
      name: 'Malaysian Ringgit',
      icon: Icons.attach_money,
      decimals: 2,
      hint: 'e.g., 45.00',
    ),
    'THB': CurrencyInfo(
      code: 'THB',
      symbol: '฿',
      name: 'Thai Baht',
      icon: Icons.attach_money,
      decimals: 2,
      hint: 'e.g., 350.00',
    ),
    'PKR': CurrencyInfo(
      code: 'PKR',
      symbol: '₨',
      name: 'Pakistani Rupee',
      icon: Icons.currency_rupee,
      decimals: 0,
      hint: 'e.g., 2800',
    ),
    'BDT': CurrencyInfo(
      code: 'BDT',
      symbol: '৳',
      name: 'Bangladeshi Taka',
      icon: Icons.currency_rupee,
      decimals: 0,
      hint: 'e.g., 1100',
    ),
    'NPR': CurrencyInfo(
      code: 'NPR',
      symbol: 'रू',
      name: 'Nepalese Rupee',
      icon: Icons.currency_rupee,
      decimals: 0,
      hint: 'e.g., 1300',
    ),
  };

  // ============================================
  // PUBLIC METHODS
  // ============================================

  /// Currency code එකෙන් CurrencyInfo එක return කරනවා
  CurrencyInfo getInfo(String? currencyCode) {
    if (currencyCode == null || currencyCode.isEmpty) {
      return _currencies['LKR']!; // Default fallback
    }
    return _currencies[currencyCode.toUpperCase()] ?? _currencies['LKR']!;
  }

  /// Price එක format කරනවා (Rs. 1,500 / $ 15.00)
  String format({
    required dynamic price,
    required String? currencyCode,
    bool withSymbol = true,
    bool withComma = true,
  }) {
    if (price == null) return withSymbol ? '${getInfo(currencyCode).symbol} 0' : '0';

    final info = getInfo(currencyCode);
    final double value = (price as num).toDouble();

    // Decimal places
    String formatted = value.toStringAsFixed(info.decimals);

    // Comma separator (1,500 / 15.00)
    if (withComma) {
      final parts = formatted.split('.');
      final intPart = parts[0];
      final decPart = parts.length > 1 ? parts[1] : '';

      // Add commas every 3 digits
      final buffer = StringBuffer();
      for (int i = 0; i < intPart.length; i++) {
        if (i > 0 && (intPart.length - i) % 3 == 0) {
          buffer.write(',');
        }
        buffer.write(intPart[i]);
      }

      formatted = decPart.isEmpty ? buffer.toString() : '${buffer.toString()}.$decPart';
    }

    return withSymbol ? '${info.symbol} $formatted' : formatted;
  }

  /// ළඟම තියෙන ගානට round කරනවා (LKR: 1500, USD: 15.00)
  double roundForCurrency({
    required double amount,
    required String? currencyCode,
  }) {
    final info = getInfo(currencyCode);
    if (info.decimals == 0) {
      return amount.roundToDouble();
    }
    return double.parse(amount.toStringAsFixed(info.decimals));
  }

  /// Currency icon එක return කරනවා
  IconData getIcon(String? currencyCode) {
    return getInfo(currencyCode).icon;
  }

  /// Currency symbol එක return කරනවා
  String getSymbol(String? currencyCode) {
    return getInfo(currencyCode).symbol;
  }

  /// Input hint එක return කරනවා
  String getHint(String? currencyCode) {
    return getInfo(currencyCode).hint;
  }

  /// Currency 2ක් same ද බලනවා
  bool isSame(String? a, String? b) {
    if (a == null || b == null) return false;
    return a.toUpperCase() == b.toUpperCase();
  }

  /// Supported currencies list එක
  List<CurrencyInfo> getSupportedCurrencies() {
    return _currencies.values.toList();
  }

  /// Display text - "Prices in LKR (Rs.)"
  String getDisplayText(String? currencyCode) {
    final info = getInfo(currencyCode);
    return 'Prices in ${info.code} (${info.symbol})';
  }
}

// ============================================
// CURRENCY INFO MODEL
// ============================================
class CurrencyInfo {
  final String code;
  final String symbol;
  final String name;
  final IconData icon;
  final int decimals;
  final String hint;

  const CurrencyInfo({
    required this.code,
    required this.symbol,
    required this.name,
    required this.icon,
    required this.decimals,
    required this.hint,
  });

  @override
  String toString() => '$code ($symbol)';
}