import 'package:flutter/material.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class DashboardStatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool fullWidth;
  final String? subtitle;
  final double? percentageChange;
  final bool showProgress;
  final double progressValue;

  const DashboardStatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
    this.fullWidth = false,
    this.subtitle,
    this.percentageChange,
    this.showProgress = false,
    this.progressValue = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ Responsive sizing
    final isTablet = context.isTablet;
    final isDark = context.isDarkMode;
    
    final padding = isTablet ? 20.0 : 16.0;
    final iconSize = isTablet ? 28.0 : 24.0;
    final valueSize = isTablet ? 28.0 : 24.0;
    final titleSize = isTablet ? 16.0 : 14.0;
    final subtitleSize = isTablet ? 13.0 : 12.0;
    final iconPadding = isTablet ? 12.0 : 10.0;
    final borderRadius = isTablet ? 20.0 : 16.0;
    final minHeight = isTablet ? 120.0 : 100.0;
    final shadowColor = isDark 
        ? Colors.black.withValues(alpha: 0.3) 
        : Colors.grey.withValues(alpha: 0.1);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        splashColor: color.withValues(alpha: 0.1),
        highlightColor: color.withValues(alpha: 0.05),
        child: Container(
          width: fullWidth ? double.infinity : null,
          constraints: BoxConstraints(
            minHeight: minHeight,
          ),
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: context.cardColor,
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: isDark 
                ? Border.all(color: Colors.grey[800]!, width: 0.5)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon and Value Row
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(iconPadding),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(
                        isTablet ? 14.0 : 12.0,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color: color,
                      size: iconSize,
                    ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: valueSize,
                          fontWeight: FontWeight.bold,
                          color: color,
                          height: 1.2,
                        ),
                      ),
                      if (percentageChange != null)
                        Row(
                          children: [
                            Icon(
                              percentageChange! >= 0
                                  ? Icons.arrow_upward
                                  : Icons.arrow_downward,
                              size: isTablet ? 16 : 14,
                              color: percentageChange! >= 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${percentageChange!.abs()}%',
                              style: TextStyle(
                                fontSize: isTablet ? 13 : 12,
                                color: percentageChange! >= 0
                                    ? Colors.green
                                    : Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Title
              Text(
                title,
                style: TextStyle(
                  fontSize: titleSize,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : Colors.grey[700],
                  height: 1.2,
                ),
              ),
              // Subtitle
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: subtitleSize,
                    color: isDark ? Colors.white70 : Colors.grey[500],
                  ),
                ),
              ],
              // Progress indicator
              if (showProgress) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progressValue.clamp(0.0, 1.0),
                    backgroundColor: isDark 
                        ? Colors.grey[800] 
                        : Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: isTablet ? 6 : 4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}