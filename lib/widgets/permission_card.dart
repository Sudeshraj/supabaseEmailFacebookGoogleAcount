import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';
import 'package:flutter_application_1/theme/app_theme.dart';
import 'package:flutter_application_1/extensions/context_extensions.dart';

class PermissionCard extends StatelessWidget {
  final VoidCallback onEnable;
  final VoidCallback onNotNow;
  final String title;
  final String message;
  final bool compact;
  final String? iconEmoji;
  final Color? accentColor;

  const PermissionCard({
    super.key,
    required this.onEnable,
    required this.onNotNow,
    required this.title,
    required this.message,
    this.compact = false,
    this.iconEmoji,
    this.accentColor,
  });

  bool get isWeb => UniversalPlatform.isWeb;
  bool get isMobile => !isWeb;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600 && screenWidth < 1200;
    final isDesktop = screenWidth >= 1200;
    
    final color = accentColor ?? AppTheme.primary;
    final icon = iconEmoji ?? '🔔';

    // ✅ Responsive padding and sizing
    final horizontalPadding = isDesktop ? 48.0 : (isTablet ? 32.0 : 16.0);
    final verticalPadding = isDesktop ? 28.0 : (isTablet ? 24.0 : 20.0);
    final iconSize = isDesktop ? 56.0 : (isTablet ? 48.0 : 40.0);
    final titleSize = isDesktop ? 20.0 : (isTablet ? 18.0 : 16.0);
    final messageSize = isDesktop ? 15.0 : (isTablet ? 14.0 : 13.0);
    final buttonHeight = isDesktop ? 56.0 : (isTablet ? 50.0 : 46.0);

    // ✅ Dark mode colors
    final textColor = isDark ? Colors.white : Colors.grey[900]!;
    final secondaryTextColor = isDark ? Colors.white70 : Colors.grey[600]!;
    final closeButtonBg = isDark ? Colors.grey[800] : Colors.grey[100];
    final closeButtonIconColor = isDark ? Colors.white60 : Colors.grey[500];
    final webInfoBg = isDark ? Colors.amber.shade900.withValues(alpha: 0.2) : Colors.amber.shade50;
    final webInfoBorder = isDark ? Colors.amber.shade700 : Colors.amber.shade200;
    final webInfoTextColor = isDark ? Colors.amber.shade300 : Colors.amber.shade800;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 12.0,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  color.withValues(alpha: 0.12),
                  const Color(0xFF1E1E1E),
                  color.withValues(alpha: 0.08),
                ]
              : [
                  color.withValues(alpha: 0.08),
                  Colors.white,
                  color.withValues(alpha: 0.05),
                ],
        ),
        borderRadius: BorderRadius.circular(
          isDesktop ? 24.0 : (isTablet ? 20.0 : 16.0),
        ),
        border: Border.all(
          color: isDark ? color.withValues(alpha: 0.3) : color.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.15 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: color.withValues(alpha: isDark ? 0.08 : 0.04),
            blurRadius: 40,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          isDesktop ? 24.0 : (isTablet ? 20.0 : 16.0),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: null,
            child: Padding(
              padding: EdgeInsets.all(verticalPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ============================================================
                  // TOP ROW: Icon + Title + Close Button
                  // ============================================================
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icon
                      Container(
                        width: iconSize,
                        height: iconSize,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: isDark
                                ? [
                                    color.withValues(alpha: 0.25),
                                    color.withValues(alpha: 0.08),
                                  ]
                                : [
                                    color.withValues(alpha: 0.15),
                                    color.withValues(alpha: 0.05),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(
                            isDesktop ? 16.0 : (isTablet ? 14.0 : 12.0),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            icon,
                            style: TextStyle(
                              fontSize: isDesktop ? 28.0 : (isTablet ? 24.0 : 20.0),
                            ),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 16),
                      
                      // Title & Message
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: titleSize,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // ✅ Always show message regardless of compact
                            const SizedBox(height: 8),
                            Text(
                              message,
                              style: TextStyle(
                                fontSize: messageSize,
                                color: secondaryTextColor,
                                height: 1.5,
                              ),
                              maxLines: isWeb ? 4 : 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // ✅ Web extra info
                            if (isWeb) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: webInfoBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: webInfoBorder,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 14,
                                      color: isDark ? Colors.amber.shade300 : Colors.amber.shade700,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'You\'ll be asked to allow notifications in your browser',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: webInfoTextColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      
                      // ✅ Close Button - Always visible
                      GestureDetector(
                        onTap: onNotNow,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: closeButtonBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: isDesktop ? 22 : 18,
                            color: closeButtonIconColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // ============================================================
                  // BOTTOM: Buttons - Single button (compact style)
                  // ============================================================
                  const SizedBox(height: 20),
                  
                  // ✅ Always single button - like compact mode
                  SizedBox(
                    width: double.infinity,
                    height: buttonHeight,
                    child: _buildEnableButton(context, color, isDesktop, isTablet, isDark),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ENABLE BUTTON
  // ============================================================
  
  Widget _buildEnableButton(
    BuildContext context,
    Color color,
    bool isDesktop,
    bool isTablet,
    bool isDark,
  ) {
    final isWeb = UniversalPlatform.isWeb;
    final buttonLabel = isWeb ? 'Enable Notifications 🌐' : 'Enable Notifications';
    
    return ElevatedButton(
      onPressed: onEnable,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: isDark ? 2 : 0,
        shadowColor: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            isDesktop ? 16.0 : (isTablet ? 14.0 : 12.0),
          ),
        ),
        textStyle: TextStyle(
          fontSize: isDesktop ? 16.0 : (isTablet ? 15.0 : 14.0),
          fontWeight: FontWeight.w600,
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 32.0 : 24.0,
          vertical: 0,
        ),
        minimumSize: const Size(0, 0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_active,
            size: isDesktop ? 22 : 18,
            color: Colors.white,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              buttonLabel,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}