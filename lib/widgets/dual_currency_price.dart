import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/currency_service.dart';

/// ✅ Displays a price in salon currency with approximate user currency
/// Example:
///   Rs. 1,000.00
///   ≈ $3.33
class DualCurrencyPrice extends StatelessWidget {
  final double salonPrice;
  final String salonCurrency;
  final String userCurrency;
  final double? exchangeRate; // 1 salon_currency = N user_currency
  final double fontSize;
  final bool isBold;
  final Color? color;
  final MainAxisAlignment mainAxisAlignment;

  const DualCurrencyPrice({
    super.key,
    required this.salonPrice,
    required this.salonCurrency,
    required this.userCurrency,
    this.exchangeRate,
    this.fontSize = 14,
    this.isBold = false,
    this.color,
    this.mainAxisAlignment = MainAxisAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    final currencyService = CurrencyService.instance;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final salonText = currencyService.format(
      price: salonPrice,
      currencyCode: salonCurrency,
      withSymbol: true,
    );

    // Same currency → only salon price
    if (salonCurrency == userCurrency ||
        exchangeRate == null ||
        exchangeRate! <= 0) {
      return Text(
        salonText,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: color ?? (isDark ? Colors.white : Colors.black87),
        ),
      );
    }

    // Convert: user_amount = salon_price × rate
    final userAmount = salonPrice * exchangeRate!;
    final userText = currencyService.format(
      price: userAmount,
      currencyCode: userCurrency,
      withSymbol: true,
    );

    final crossAxis = mainAxisAlignment == MainAxisAlignment.center
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;

    return Column(
      crossAxisAlignment: crossAxis,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          salonText,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color ?? (isDark ? Colors.white : Colors.black87),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '≈ $userText',
          style: TextStyle(
            fontSize: fontSize - 2,
            fontStyle: FontStyle.italic,
            color: isDark ? Colors.white60 : Colors.grey[600],
          ),
        ),
      ],
    );
  }
}