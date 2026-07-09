import 'package:flutter/material.dart';
import 'package:universal_platform/universal_platform.dart';

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
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600 && screenWidth < 1200;
    final isDesktop = screenWidth >= 1200;
    
    final color = accentColor ?? const Color(0xFFFF6B8B);
    final icon = iconEmoji ?? '🔔';

    // ✅ Responsive padding and sizing
    final horizontalPadding = isDesktop ? 48.0 : (isTablet ? 32.0 : 16.0);
    final verticalPadding = isDesktop ? 28.0 : (isTablet ? 24.0 : 20.0);
    final iconSize = isDesktop ? 56.0 : (isTablet ? 48.0 : 40.0);
    final titleSize = isDesktop ? 20.0 : (isTablet ? 18.0 : 16.0);
    final messageSize = isDesktop ? 15.0 : (isTablet ? 14.0 : 13.0);
    final buttonHeight = isDesktop ? 56.0 : (isTablet ? 50.0 : 46.0);

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 12.0,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.08),
            Colors.white,
            color.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(
          isDesktop ? 24.0 : (isTablet ? 20.0 : 16.0),
        ),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: color.withValues(alpha: 0.04),
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
            onTap: null, // No ripple on whole card
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
                            colors: [
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
                                color: Colors.grey[900],
                                height: 1.2,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 8),
                              Text(
                                message,
                                style: TextStyle(
                                  fontSize: messageSize,
                                  color: Colors.grey[600],
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
                                    color: Colors.amber.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.amber.shade200,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        size: 14,
                                        color: Colors.amber.shade700,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'You\'ll be asked to allow notifications in your browser',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.amber.shade800,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                      
                      // Close Button (Not Now)
                      if (!compact)
                        GestureDetector(
                          onTap: onNotNow,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              size: isDesktop ? 22 : 18,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                    ],
                  ),
                  
                  // ============================================================
                  // BOTTOM: Buttons
                  // ============================================================
                  const SizedBox(height: 20),
                  
                  // ✅ Responsive Buttons Row
                  if (compact)
                    // Compact: Single button
                    SizedBox(
                      width: double.infinity,
                      height: buttonHeight,
                      child: _buildEnableButton(context, color, isDesktop, isTablet),
                    )
                  else
                    // Full: Two buttons
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isSmallScreen = constraints.maxWidth < 400;
                        
                        if (isSmallScreen) {
                          // Stack buttons vertically on small screens
                          return Column(
                            children: [
                              SizedBox(
                                width: double.infinity,
                                height: buttonHeight,
                                child: _buildEnableButton(context, color, isDesktop, isTablet),
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                height: buttonHeight * 0.8,
                                child: _buildNotNowButton(context),
                              ),
                            ],
                          );
                        } else {
                          // Side by side on larger screens
                          return Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: SizedBox(
                                  height: buttonHeight,
                                  child: _buildEnableButton(context, color, isDesktop, isTablet),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 1,
                                child: SizedBox(
                                  height: buttonHeight,
                                  child: _buildNotNowButton(context),
                                ),
                              ),
                            ],
                          );
                        }
                      },
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
  ) {
    final isWeb = UniversalPlatform.isWeb;
    final buttonLabel = isWeb ? 'Enable Notifications 🌐' : 'Enable Notifications';
    
    return ElevatedButton(
      onPressed: onEnable,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
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
          Text(buttonLabel),
        ],
      ),
    );
  }

  // ============================================================
  // NOT NOW BUTTON
  // ============================================================
  
  Widget _buildNotNowButton(BuildContext context) {
    return OutlinedButton(
      onPressed: onNotNow,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.grey[600],
        side: BorderSide(
          color: Colors.grey[300]!,
          width: 1.5,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.thumb_up_off_alt_outlined,
            size: 16,
            color: Colors.grey[500],
          ),
          const SizedBox(width: 8),
          const Text('Not Now'),
        ],
      ),
    );
  }
}