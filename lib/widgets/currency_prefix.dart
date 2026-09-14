import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/currency_service.dart';

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
          CurrencyService.instance.getIcon(symbol),
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
              CurrencyService.instance.getIcon(symbol),
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