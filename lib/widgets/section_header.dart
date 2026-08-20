import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

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
    // ✅ Responsive sizing using Context Extensions
    final isTablet = context.isTablet;
    final isDark = context.isDarkMode;
    final primaryColor = context.primaryColor;
    
    final horizontalPadding = padding?.horizontal ?? (isTablet ? 24.0 : 16.0);
    final verticalPadding = padding?.vertical ?? (isTablet ? 12.0 : 8.0);
    final titleSize = fontSize ?? (isTablet ? 22.0 : 18.0);
    final actionSize = isTablet ? 15.0 : 13.0;
    final accentColorValue = accentColor ?? primaryColor;
    
    final textColor = context.textColor;
    final decorationColor = isDark 
        ? accentColorValue.withValues(alpha: 0.8) 
        : accentColorValue;
    
    // ✅ Fixed: Use double values
    final buttonMinWidth = isTablet ? 56.0 : 48.0;
    final buttonMinHeight = isTablet ? 44.0 : 36.0;

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
                width: isTablet ? 5.0 : 4.0,
                height: isTablet ? 24.0 : 20.0,
                decoration: BoxDecoration(
                  color: decorationColor,
                  borderRadius: BorderRadius.circular(isTablet ? 3 : 2),
                ),
              ),
              SizedBox(width: isTablet ? 12.0 : 8.0),
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
                minimumSize: Size(buttonMinWidth, buttonMinHeight),
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 16.0 : 12.0,
                  vertical: isTablet ? 10.0 : 6.0,
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
                  Text(
                    actionText ?? 'View All',
                    style: TextStyle(
                      color: accentColorValue,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: isTablet ? 14.0 : 12.0,
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