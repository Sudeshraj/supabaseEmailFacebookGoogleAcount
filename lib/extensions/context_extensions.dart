import 'package:flutter/material.dart';
import 'package:flutter_application_1/theme/app_theme.dart';

extension ContextThemeExtension on BuildContext {
  // ============================================================
  // ✅ 1. THEME COLORS (AppTheme එකෙන්)
  // ============================================================
  
  ThemeData get theme => Theme.of(this);
  ColorScheme get colorScheme => theme.colorScheme;
  bool get isDarkMode => theme.brightness == Brightness.dark;
  
  // Primary colors
  Color get primaryColor => colorScheme.primary;
  Color get secondaryColor => colorScheme.secondary;
  Color get surfaceColor => colorScheme.surface;
  Color get backgroundColor => colorScheme.surface;
  
  // Text colors (auto dark/light)
  Color get textColor => isDarkMode 
      ? AppTheme.darkText 
      : AppTheme.lightText;
  
  Color get secondaryTextColor => isDarkMode 
      ? AppTheme.darkTextSecondary 
      : AppTheme.lightTextSecondary;
  
  Color get cardColor => theme.cardColor;
  Color get dividerColor => theme.dividerColor;
  
  // Status colors
  Color get successColor => AppTheme.success;
  Color get warningColor => AppTheme.warning;
  Color get errorColor => AppTheme.error;
  Color get infoColor => AppTheme.info;
  
  // ============================================================
  // ✅ 2. TEXT STYLES
  // ============================================================
  
  TextStyle get headlineLarge => theme.textTheme.headlineLarge!;
  TextStyle get headlineMedium => theme.textTheme.headlineMedium!;
  TextStyle get headlineSmall => theme.textTheme.headlineSmall!;
  TextStyle get titleLarge => theme.textTheme.titleLarge!;
  TextStyle get titleMedium => theme.textTheme.titleMedium!;
  TextStyle get titleSmall => theme.textTheme.titleSmall!;
  TextStyle get bodyLarge => theme.textTheme.bodyLarge!;
  TextStyle get bodyMedium => theme.textTheme.bodyMedium!;
  TextStyle get bodySmall => theme.textTheme.bodySmall!;
  
  // ============================================================
  // ✅ 3. SCREEN SIZE CHECKS (Android 16 Responsive)
  // ============================================================
  
  Size get screenSize => MediaQuery.of(this).size;
  double get screenWidth => screenSize.width;
  double get screenHeight => screenSize.height;
  
  bool get isMobile => screenWidth < 600;
  bool get isTablet => screenWidth >= 600 && screenWidth < 1200;
  bool get isDesktop => screenWidth >= 1200;
  bool get isWeb => screenWidth > 800;
  
  // ============================================================
  // ✅ 4. RESPONSIVE SIZES
  // ============================================================
  
  double get responsivePadding => isTablet ? 24.0 : 16.0;
  double get responsiveFontSize => isTablet ? 18.0 : 14.0;
  double get responsiveIconSize => isTablet ? 28.0 : 22.0;
  
  // ============================================================
  // ✅ 5. SNACKBAR HELPERS
  // ============================================================
  
  void showSnackBar(String message, {Color? color}) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? primaryColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
  
  void showSuccessSnackBar(String message) {
    showSnackBar(message, color: successColor);
  }
  
  void showErrorSnackBar(String message) {
    showSnackBar(message, color: errorColor);
  }
  
  void showWarningSnackBar(String message) {
    showSnackBar(message, color: warningColor);
  }
}