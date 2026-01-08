// 📁 lib/utils/constants.dart
// ===========================================
// APP CONSTANTS - NO ENVIRONMENT VARIABLES
// ===========================================

class AppConstants {
  // ========== 📱 APP INFORMATION ==========
  static const String appName = 'AutoLogin App';
  static const String appVersion = '1.0.0';
  static const String appBuildNumber = '1';
  
  // ========== 🗺️ APP ROUTES ==========
  static const String splashRoute = '/';
  static const String loginRoute = '/login';
  static const String registerRoute = '/register';
  static const String homeRoute = '/home';
  static const String continueRoute = '/continue';
  static const String profileRoute = '/profile';
  static const String settingsRoute = '/settings';
  
  // ========== 💾 STORAGE KEYS ==========
  // SharedPreferences keys
  static const String isFirstTimeKey = 'is_first_time';
  static const String isLoggedInKey = 'is_logged_in';
  static const String userIdKey = 'user_id';
  static const String userEmailKey = 'user_email';
  static const String userNameKey = 'user_name';
  static const String userFullNameKey = 'user_full_name';
  static const String userProfileImageKey = 'user_profile_image';
  static const String sessionTokenKey = 'session_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String accessTokenKey = 'access_token';
  
  // Continue screen keys
  static const String continueUserIdKey = 'continue_user_id';
  static const String continueUserEmailKey = 'continue_user_email';
  static const String continueUserNameKey = 'continue_user_name';
  static const String continueUserImageKey = 'continue_user_image';
  static const String showContinueScreenKey = 'show_continue_screen';
  
  // Settings keys
  static const String darkModeKey = 'dark_mode';
  static const String notificationsKey = 'notifications';
  static const String biometricsKey = 'biometrics';
  static const String languageKey = 'language';
  
  // ========== 🔐 VALIDATION RULES ==========
  static const int minPasswordLength = 6;
  static const int maxPasswordLength = 128;
  static const int minNameLength = 2;
  static const int maxNameLength = 50;
  static const int minEmailLength = 5;
  static const int maxEmailLength = 254;
  static const int otpLength = 6;
  static const int phoneNumberLength = 10;
  
  // ========== 🎨 UI CONSTANTS ==========
  // Spacing
  static const double spacingXSmall = 4.0;
  static const double spacingSmall = 8.0;
  static const double spacingMedium = 12.0;
  static const double spacingLarge = 16.0;
  static const double spacingXLarge = 20.0;
  static const double spacingXXLarge = 24.0;
  static const double spacingXXXLarge = 32.0;
  
  // Padding
  static const double paddingXSmall = 4.0;
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 12.0;
  static const double paddingLarge = 16.0;
  static const double paddingXLarge = 20.0;
  static const double paddingXXLarge = 24.0;
  static const double paddingXXXLarge = 32.0;
  
  // Border Radius
  static const double borderRadiusSmall = 4.0;
  static const double borderRadiusMedium = 8.0;
  static const double borderRadiusLarge = 12.0;
  static const double borderRadiusXLarge = 16.0;
  static const double borderRadiusXXLarge = 20.0;
  static const double borderRadiusCircle = 50.0;
  
  // Sizes
  static const double buttonHeight = 56.0;
  static const double buttonHeightSmall = 48.0;
  static const double buttonHeightLarge = 64.0;
  static const double appBarHeight = 56.0;
  static const double bottomNavHeight = 56.0;
  static const double iconSizeSmall = 16.0;
  static const double iconSizeMedium = 24.0;
  static const double iconSizeLarge = 32.0;
  static const double avatarSizeSmall = 40.0;
  static const double avatarSizeMedium = 60.0;
  static const double avatarSizeLarge = 80.0;
  static const double avatarSizeXLarge = 100.0;
  
  // Elevation
  static const double elevationNone = 0.0;
  static const double elevationLow = 2.0;
  static const double elevationMedium = 4.0;
  static const double elevationHigh = 8.0;
  static const double elevationXHigh = 12.0;
  
  // ========== ⏱️ TIME CONSTANTS ==========
  static const Duration splashDuration = Duration(seconds: 2);
  static const Duration snackbarDurationShort = Duration(seconds: 2);
  static const Duration snackbarDurationMedium = Duration(seconds: 3);
  static const Duration snackbarDurationLong = Duration(seconds: 4);
  static const Duration apiTimeoutDuration = Duration(seconds: 30);
  static const Duration debounceDuration = Duration(milliseconds: 500);
  static const Duration typingDelay = Duration(milliseconds: 300);
  static const Duration sessionRefreshInterval = Duration(minutes: 55);
  static const Duration autoLogoutDuration = Duration(hours: 24);
  
  // ========== 🎯 ERROR MESSAGES ==========
  static const String errorNetwork = 'Network error. Please check your connection.';
  static const String errorServer = 'Server error. Please try again later.';
  static const String errorTimeout = 'Request timeout. Please try again.';
  static const String errorUnknown = 'An unexpected error occurred.';
  static const String errorInvalidCredentials = 'Invalid email or password.';
  static const String errorEmailInUse = 'Email already in use.';
  static const String errorWeakPassword = 'Password is too weak.';
  static const String errorInvalidEmail = 'Please enter a valid email address.';
  static const String errorPasswordLength = 'Password must be at least 6 characters.';
  static const String errorNameLength = 'Name must be at least 2 characters.';
  static const String errorPasswordsNotMatch = 'Passwords do not match.';
  static const String errorSessionExpired = 'Session expired. Please login again.';
  static const String errorBiometricNotAvailable = 'Biometric authentication not available.';
  static const String errorBiometricNotEnrolled = 'No biometric enrolled.';
  static const String errorBiometricLocked = 'Too many failed attempts. Try again later.';
  
  // ========== ✅ SUCCESS MESSAGES ==========
  static const String successLogin = 'Login successful!';
  static const String successRegister = 'Registration successful!';
  static const String successLogout = 'Logged out successfully.';
  static const String successProfileUpdate = 'Profile updated successfully.';
  static const String successPasswordChange = 'Password changed successfully.';
  static const String successAutoLogin = 'Auto login successful!';
  static const String successSessionRestored = 'Session restored successfully.';
  
  // ========== ℹ️ INFO MESSAGES ==========
  static const String infoContinueLogin = 'Tap your profile to continue';
  static const String infoSessionSaved = 'Session saved for next time';
  static const String infoBiometricEnabled = 'Biometric login enabled';
  static const String infoAutoLoginEnabled = 'Auto login is enabled';
  
  // ========== 🚨 WARNING MESSAGES ==========
  static const String warningSessionExpiring = 'Your session will expire soon';
  static const String warningOldPassword = 'You are using an old password';
  static const String warningMultipleDevices = 'Logged in from multiple devices';
  
  // ========== 🔗 API ENDPOINTS ==========
  // Note: These should come from .env, but as fallback:
  static const String defaultSupabaseUrl = 'https://your-project.supabase.co';
  static const String defaultSupabaseAnonKey = 'your-anon-key-here';
  
  // API Paths (if using REST API directly)
  static const String apiAuthSignUp = '/auth/v1/signup';
  static const String apiAuthSignIn = '/auth/v1/token';
  static const String apiAuthSignOut = '/auth/v1/logout';
  static const String apiAuthUser = '/auth/v1/user';
  static const String apiAuthRefresh = '/auth/v1/refresh';
  static const String apiProfiles = '/rest/v1/profiles';
  
  // ========== 🗄️ DATABASE TABLES ==========
  static const String tableProfiles = 'profiles';
  static const String tableSessions = 'sessions';
  static const String tableSettings = 'settings';
  static const String tableActivities = 'activities';
  
  // ========== 🌍 LOCALIZATION ==========
  static const String defaultLanguage = 'en';
  static const String defaultCountry = 'US';
  static const String defaultLocale = 'en_US';
  
  // Supported languages
  static const Map<String, String> supportedLanguages = {
    'en': 'English',
    'si': 'සිංහල',
    'ta': 'தமிழ்',
  };
  
  // ========== 🎭 ANIMATION DURATIONS ==========
  static const Duration animationFast = Duration(milliseconds: 150);
  static const Duration animationNormal = Duration(milliseconds: 300);
  static const Duration animationSlow = Duration(milliseconds: 500);
  static const Duration animationVerySlow = Duration(milliseconds: 800);
  
  // ========== 🔧 DEBUG SETTINGS ==========
  static const bool enableDebugLogs = true;
  static const bool enableNetworkLogs = true;
  static const bool enableDatabaseLogs = false;
  static const bool enableAnalytics = true;
  static const bool enableCrashReporting = true;
  
  // ========== 📊 PAGINATION ==========
  static const int itemsPerPage = 10;
  static const int maxItemsPerPage = 50;
  static const int initialPage = 1;
  
  // ========== 🎪 FEATURE FLAGS ==========
  static const bool featureBiometricLogin = true;
  static const bool featureDarkMode = true;
  static const bool featureNotifications = true;
  static const bool featureOfflineMode = false;
  static const bool featureMultiLanguage = true;
  static const bool featureSocialLogin = false;
  static const bool featureTwoFactorAuth = false;
  
  // ========== 🎨 DESIGN SYSTEM ==========
  // Font Sizes
  static const double fontSizeXSmall = 10.0;
  static const double fontSizeSmall = 12.0;
  static const double fontSizeMedium = 14.0;
  static const double fontSizeLarge = 16.0;
  static const double fontSizeXLarge = 18.0;
  static const double fontSizeXXLarge = 20.0;
  static const double fontSizeXXXLarge = 24.0;
  static const double fontSizeDisplaySmall = 32.0;
  static const double fontSizeDisplayMedium = 40.0;
  static const double fontSizeDisplayLarge = 48.0;
  
  // // Font Weights
  // static const FontWeight fontWeightLight = FontWeight.w300;
  // static const FontWeight fontWeightRegular = FontWeight.w400;
  // static const FontWeight fontWeightMedium = FontWeight.w500;
  // static const FontWeight fontWeightSemiBold = FontWeight.w600;
  // static const FontWeight fontWeightBold = FontWeight.w700;
  
  // Letter Spacing
  static const double letterSpacingTight = -0.5;
  static const double letterSpacingNormal = 0.0;
  static const double letterSpacingWide = 0.5;
  static const double letterSpacingWider = 1.0;
  
  // Line Heights
  static const double lineHeightTight = 1.0;
  static const double lineHeightNormal = 1.2;
  static const double lineHeightRelaxed = 1.5;
  static const double lineHeightLoose = 2.0;
  
  // ========== 🎮 APP BEHAVIOR ==========
  static const int maxLoginAttempts = 5;
  static const int sessionTimeoutMinutes = 60;
  static const int cacheDurationHours = 24;
  static const int maxFileSizeMB = 10;
  static const List<String> allowedImageTypes = [
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp'
  ];
  
  // ========== 🔔 NOTIFICATION CHANNELS ==========
  static const String notificationChannelGeneral = 'general';
  static const String notificationChannelImportant = 'important';
  static const String notificationChannelSilent = 'silent';
  
  // ========== 🛠️ UTILITY METHODS ==========
  
  // Get spacing based on size name
  static double getSpacing(String size) {
    switch (size) {
      case 'xsmall': return spacingXSmall;
      case 'small': return spacingSmall;
      case 'medium': return spacingMedium;
      case 'large': return spacingLarge;
      case 'xlarge': return spacingXLarge;
      case 'xxlarge': return spacingXXLarge;
      case 'xxxlarge': return spacingXXXLarge;
      default: return spacingMedium;
    }
  }
  
  // Get padding based on size name
  static double getPadding(String size) {
    switch (size) {
      case 'xsmall': return paddingXSmall;
      case 'small': return paddingSmall;
      case 'medium': return paddingMedium;
      case 'large': return paddingLarge;
      case 'xlarge': return paddingXLarge;
      case 'xxlarge': return paddingXXLarge;
      case 'xxxlarge': return paddingXXXLarge;
      default: return paddingMedium;
    }
  }
  
  // Get border radius based on size name
  static double getBorderRadius(String size) {
    switch (size) {
      case 'small': return borderRadiusSmall;
      case 'medium': return borderRadiusMedium;
      case 'large': return borderRadiusLarge;
      case 'xlarge': return borderRadiusXLarge;
      case 'xxlarge': return borderRadiusXXLarge;
      case 'circle': return borderRadiusCircle;
      default: return borderRadiusMedium;
    }
  }
  
  // Get font size based on size name
  static double getFontSize(String size) {
    switch (size) {
      case 'xsmall': return fontSizeXSmall;
      case 'small': return fontSizeSmall;
      case 'medium': return fontSizeMedium;
      case 'large': return fontSizeLarge;
      case 'xlarge': return fontSizeXLarge;
      case 'xxlarge': return fontSizeXXLarge;
      case 'xxxlarge': return fontSizeXXXLarge;
      case 'displaySmall': return fontSizeDisplaySmall;
      case 'displayMedium': return fontSizeDisplayMedium;
      case 'displayLarge': return fontSizeDisplayLarge;
      default: return fontSizeMedium;
    }
  }
  
  // Validate email format
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    );
    return emailRegex.hasMatch(email);
  }
  
  // Validate password strength
  static bool isStrongPassword(String password) {
    if (password.length < minPasswordLength) return false;
    
    // Check for at least one uppercase letter
    if (!RegExp(r'[A-Z]').hasMatch(password)) return false;
    
    // Check for at least one lowercase letter
    if (!RegExp(r'[a-z]').hasMatch(password)) return false;
    
    // Check for at least one digit
    if (!RegExp(r'[0-9]').hasMatch(password)) return false;
    
    // Check for at least one special character
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) return false;
    
    return true;
  }
  
  // Format date for display
  static String formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
  
  // Format time for display
  static String formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
  
  // Get initials from name
  static String getInitials(String name) {
    if (name.isEmpty) return '?';
    
    final parts = name.split(' ');
    if (parts.length == 1) {
      return parts[0][0].toUpperCase();
    } else {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
  }
  
  // Truncate text with ellipsis
  static String truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }
  
  // ========== 📝 PRINT CONFIGURATION ==========
  static void printConfig() {
    if (!enableDebugLogs) return;
    
    // print('\n' + '═' * 50);
    // print('📱 ${appName.toUpperCase()} CONFIGURATION');
    // print('═' * 50);
    
    // print('📦 App Info:');
    // print('   • Name: $appName');
    // print('   • Version: $appVersion');
    // print('   • Build: $appBuildNumber');
    
    // print('\n🎨 UI Constants:');
    // print('   • Default Padding: ${paddingLarge}px');
    // print('   • Button Height: ${buttonHeight}px');
    // print('   • Border Radius: ${borderRadiusLarge}px');
    
    // print('\n⏱️  Time Constants:');
    // print('   • Splash Duration: ${splashDuration.inSeconds}s');
    // print('   • API Timeout: ${apiTimeoutDuration.inSeconds}s');
    // print('   • Session Refresh: ${sessionRefreshInterval.inMinutes}m');
    
    // print('\n🔐 Security:');
    // print('   • Min Password: $minPasswordLength chars');
    // print('   • Max Login Attempts: $maxLoginAttempts');
    // print('   • Session Timeout: ${sessionTimeoutMinutes}m');
    
    // print('\n🚀 Feature Flags:');
    // print('   • Biometric Login: ${featureBiometricLogin ? '✅' : '❌'}');
    // print('   • Dark Mode: ${featureDarkMode ? '✅' : '❌'}');
    // print('   • Notifications: ${featureNotifications ? '✅' : '❌'}');
    // print('   • Multi Language: ${featureMultiLanguage ? '✅' : '❌'}');
    
    // print('\n🐛 Debug Settings:');
    // print('   • Debug Logs: ${enableDebugLogs ? '✅' : '❌'}');
    // print('   • Network Logs: ${enableNetworkLogs ? '✅' : '❌'}');
    // print('   • Analytics: ${enableAnalytics ? '✅' : '❌'}');
    
    // print('═' * 50 + '\n');
  }
  
  // ========== 🎯 APP-RELATED CONSTANTS ==========
  
  // App Store URLs
  static const String appStoreUrl = 'https://apps.apple.com/app/idYOUR_APP_ID';
  static const String playStoreUrl = 'https://play.google.com/store/apps/details?id=YOUR_PACKAGE_NAME';
  static const String privacyPolicyUrl = 'https://yourapp.com/privacy';
  static const String termsOfServiceUrl = 'https://yourapp.com/terms';
  static const String supportUrl = 'https://yourapp.com/support';
  
  // Social Media
  static const String twitterUrl = 'https://twitter.com/yourapp';
  static const String facebookUrl = 'https://facebook.com/yourapp';
  static const String instagramUrl = 'https://instagram.com/yourapp';
  static const String linkedinUrl = 'https://linkedin.com/company/yourapp';
  
  // Contact Information
  static const String supportEmail = 'support@yourapp.com';
  static const String businessEmail = 'hello@yourapp.com';
  static const String contactPhone = '+1 (555) 123-4567';
  static const String companyAddress = '123 App Street, Tech City, TC 12345';
  
  // Company Info
  static const String companyName = 'Your App Company';
  static const String companyWebsite = 'https://yourapp.com';
  static const int foundedYear = 2024;
  
  // ========== 🔄 STATE MANAGEMENT KEYS ==========
  static const String authStateKey = 'auth_state';
  static const String userStateKey = 'user_state';
  static const String settingsStateKey = 'settings_state';
  static const String themeStateKey = 'theme_state';
  static const String languageStateKey = 'language_state';
  
  // ========== 🎪 EVENT NAMES (for analytics) ==========
  static const String eventAppLaunch = 'app_launch';
  static const String eventLogin = 'login';
  static const String eventRegister = 'register';
  static const String eventLogout = 'logout';
  static const String eventAutoLogin = 'auto_login';
  static const String eventProfileView = 'profile_view';
  static const String eventProfileUpdate = 'profile_update';
  static const String eventSettingsChange = 'settings_change';
  static const String eventError = 'error_occurred';
  static const String eventSessionExpired = 'session_expired';
  static const String eventBiometricSuccess = 'biometric_success';
  static const String eventBiometricFailed = 'biometric_failed';
}