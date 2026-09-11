import 'package:flutter/material.dart';

// ============================================
// CURRENCY DISPLAY TYPE
// ============================================
enum CurrencyDisplayType {
  /// Text එකෙන් පෙන්නනවා (Rs., $, £, €)
  text,
  
  /// Material icon එකකින් පෙන්නනවා
  icon,
  
  /// Text + Icon දෙකම එකට
  both,
}

// ============================================
// CURRENCY PREFIX WIDGET
// ============================================
class CurrencyPrefix extends StatelessWidget {
  final String symbol;
  final CurrencyDisplayType type;
  final Color? color;
  final double fontSize;
  final double iconSize;
  final FontWeight fontWeight;
  final EdgeInsetsGeometry? padding;

  const CurrencyPrefix({
    super.key,
    required this.symbol,
    this.type = CurrencyDisplayType.text,
    this.color,
    this.fontSize = 16,
    this.iconSize = 20,
    this.fontWeight = FontWeight.bold,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ??
        (Theme.of(context).brightness == Brightness.dark
            ? Colors.white70
            : Colors.grey);

    switch (type) {
      case CurrencyDisplayType.text:
        return _buildText(effectiveColor);
      case CurrencyDisplayType.icon:
        return _buildIcon(effectiveColor);
      case CurrencyDisplayType.both:
        return _buildBoth(effectiveColor);
    }
  }

  Widget _buildText(Color effectiveColor) {
    return Center(
      widthFactor: 1.0,
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          symbol,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: effectiveColor,
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(Color effectiveColor) {
    return Center(
      widthFactor: 1.0,
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 4),
        child: Icon(
          CurrencyHelper.getIcon(symbol),
          size: iconSize,
          color: effectiveColor,
        ),
      ),
    );
  }

  Widget _buildBoth(Color effectiveColor) {
    return Center(
      widthFactor: 1.0,
      child: Padding(
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CurrencyHelper.getIcon(symbol),
              size: iconSize * 0.85,
              color: effectiveColor,
            ),
            const SizedBox(width: 4),
            Text(
              symbol,
              style: TextStyle(
                fontSize: fontSize * 0.9,
                fontWeight: fontWeight,
                color: effectiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================
// CURRENCY HELPER (Static utilities)
// ============================================
class CurrencyHelper {
  CurrencyHelper._();

  static const Map<String, String> _symbols = {
    'LKR': 'Rs.',
    'USD': '\$',
    'INR': '₹',
    'GBP': '£',
    'EUR': '€',
    'AUD': 'A\$',
    'CAD': 'C\$',
    'SGD': 'S\$',
    'NZD': 'NZ\$',
    'JPY': '¥',
    'CNY': '¥',
    'CHF': 'CHF',
    'MYR': 'RM',
    'THB': '฿',
    'AED': 'د.إ',
    'PKR': '₨',
    'BDT': '৳',
    'NPR': 'रू',
  };

  static String getSymbol(String code) {
    return _symbols[code.toUpperCase()] ?? code;
  }

  static IconData getIcon(String code) {
    switch (code.toUpperCase()) {
      case 'USD':
      case 'AUD':
      case 'CAD':
      case 'SGD':
      case 'NZD':
      case 'MYR':
      case 'THB':
      case 'CHF':
      case 'AED':
        return Icons.attach_money;
      case 'GBP':
        return Icons.currency_pound;
      case 'EUR':
        return Icons.euro;
      case 'JPY':
      case 'CNY':
        return Icons.currency_yen;
      case 'LKR':
      case 'INR':
      case 'PKR':
      case 'BDT':
      case 'NPR':
        return Icons.currency_rupee;
      default:
        return Icons.attach_money;
    }
  }

  static bool usesDecimals(String code) {
    const noDecimals = ['LKR', 'INR', 'JPY', 'PKR', 'BDT', 'NPR'];
    return !noDecimals.contains(code.toUpperCase());
  }

  static String getHint(String code) {
    return usesDecimals(code) ? 'e.g., 15.00' : 'e.g., 1500';
  }

  static String formatPrice({
    required dynamic price,
    required String currencyCode,
    String? symbol,
    bool withSymbol = true,
    bool withComma = true,
  }) {
    if (price == null) {
      return withSymbol
          ? '${symbol ?? getSymbol(currencyCode)} 0'
          : '0';
    }

    final effectiveSymbol = symbol ?? getSymbol(currencyCode);
    final double value = (price as num).toDouble();
    final int decimals = usesDecimals(currencyCode) ? 2 : 0;

    String formatted = value.toStringAsFixed(decimals);

    if (withComma) {
      final parts = formatted.split('.');
      final intPart = parts[0];
      final decPart = parts.length > 1 ? parts[1] : '';

      final buffer = StringBuffer();
      for (int i = 0; i < intPart.length; i++) {
        if (i > 0 && (intPart.length - i) % 3 == 0) {
          buffer.write(',');
        }
        buffer.write(intPart[i]);
      }

      formatted = decPart.isEmpty
          ? buffer.toString()
          : '${buffer.toString()}.$decPart';
    }

    return withSymbol ? '$effectiveSymbol $formatted' : formatted;
  }
}