import 'package:flutter/material.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onActionPressed;
  final bool showViewAll;
  final Color? accentColor;
  final double? fontSize;
  final EdgeInsetsGeometry? padding;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onActionPressed,
    this.showViewAll = true,
    this.accentColor,
    this.fontSize,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ Responsive sizing
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;
    
    final horizontalPadding = padding?.horizontal ?? (isTablet ? 24.0 : 16.0);
    final verticalPadding = padding?.vertical ?? (isTablet ? 12.0 : 8.0);
    final titleSize = fontSize ?? (isTablet ? 22.0 : 18.0);
    final actionSize = isTablet ? 15.0 : 13.0;
    final accentColorValue = accentColor ?? Theme.of(context).primaryColor;
    
    // ✅ Use isDark for dark mode support
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final decorationColor = isDark 
        ? accentColorValue.withValues(alpha: 0.8) 
        : accentColorValue;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Title with decoration
          Row(
            children: [
              Container(
                width: isTablet ? 5 : 4,
                height: isTablet ? 24 : 20,
                decoration: BoxDecoration(
                  color: decorationColor,
                  borderRadius: BorderRadius.circular(isTablet ? 3 : 2),
                ),
              ),
              SizedBox(width: isTablet ? 12 : 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),

          // View All button
          if (showViewAll)
            TextButton(
              onPressed: onActionPressed,
              style: TextButton.styleFrom(
                foregroundColor: accentColorValue,
                minimumSize: Size(
                  isTablet ? 56 : 48,
                  isTablet ? 44 : 36,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 16 : 12,
                  vertical: isTablet ? 10 : 6,
                ),
                textStyle: TextStyle(
                  fontSize: actionSize,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionText ?? 'View All'),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: isTablet ? 14 : 12,
                    color: accentColorValue,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}