import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvironmentManager {
  // Singleton instance
  static final EnvironmentManager _instance = EnvironmentManager._internal();
  factory EnvironmentManager() => _instance;
  EnvironmentManager._internal();

  // Initialize environment based on flavor
  Future<void> init({String flavor = 'development'}) async {
    String envFile;
    
    switch (flavor) {
      case 'production':
        envFile = '.env.production';
        break;
      case 'staging':
        envFile = '.env.staging';
        break;
      case 'test':
        envFile = '.env.test';
        break;
      default:
        envFile = '.env';
    }
    
    try {
      await dotenv.load(fileName: envFile);
      if (debugMode) print('✅ Loaded environment: $flavor from $envFile');
    } catch (e) {
      // Fallback to default .env
      try {
        await dotenv.load(fileName: '.env');
        if (debugMode) print('⚠️  Using default .env file');
      } catch (e2) {
        throw Exception('Failed to load any environment file: $e2');
      }
    }
  }

  // ========== REQUIRED CONFIGURATION ==========
  
  String get supabaseUrl {
    return _getRequired('SUPABASE_URL');
  }

  String get supabaseAnonKey {
    return _getRequired('SUPABASE_ANON_KEY');
  }

  String get appName {
    return dotenv.env['APP_NAME'] ?? 'MySalon App';
  }

  String get appVersion {
    return dotenv.env['APP_VERSION'] ?? '1.0.0';
  }

  String get environment {
    return dotenv.env['ENVIRONMENT'] ?? 'development';
  }

  // ========== GOOGLE OAUTH CONFIGURATION ==========
  
  String get googleWebClientId {
    return dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
  }

  String get googleAndroidClientId {
    return dotenv.env['GOOGLE_ANDROID_CLIENT_ID'] ?? googleWebClientId;
  }

  String get googleIosClientId {
    return dotenv.env['GOOGLE_IOS_CLIENT_ID'] ?? googleWebClientId;
  }

  String get googleWebClientSecret {
    return dotenv.env['GOOGLE_WEB_CLIENT_SECRET'] ?? '';
  }

  bool get enableGoogleOAuth {
    return dotenv.env['ENABLE_GOOGLE_OAUTH'] != 'false' && 
           googleWebClientId.isNotEmpty && 
           googleWebClientSecret.isNotEmpty;
  }

  // ========== FACEBOOK OAUTH CONFIGURATION ==========
  
  String get facebookAppId {
    return dotenv.env['FACEBOOK_APP_ID'] ?? '';
  }

  String get facebookClientToken {
    return dotenv.env['FACEBOOK_CLIENT_TOKEN'] ?? '';
  }

  bool get enableFacebookOAuth {
    return dotenv.env['ENABLE_FACEBOOK_OAUTH'] != 'false' && 
           facebookAppId.isNotEmpty && 
           facebookClientToken.isNotEmpty;
  }

  // ========== APPLE OAUTH CONFIGURATION ==========
  
  /// 🔥 NEW: Apple Service ID (from Apple Developer Console)
  String get appleServiceId {
    return dotenv.env['APPLE_SERVICE_ID'] ?? '';
  }

  /// 🔥 NEW: Apple redirect URL
  String get appleRedirectUrl {
    return dotenv.env['APPLE_REDIRECT_URL'] ?? 'myapp://auth/callback';
  }

  /// 🔥 NEW: Enable/disable Apple OAuth
  bool get enableAppleOAuth {
    return dotenv.env['ENABLE_APPLE_OAUTH'] != 'false';
  }

  // ========== REDIRECT URL CONFIGURATION ==========
  
  String get webRedirectUrl {
    final customUrl = dotenv.env['WEB_REDIRECT_URL'];
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    }
    
    // Default URLs based on environment
    if (isProduction) {
      return 'https://yourdomain.com/auth/callback';
    } else if (isStaging) {
      return 'https://staging.yourdomain.com/auth/callback';
    } else {
       return '${Uri.base.origin}/auth/callback';     
    }
  }

  String get mobileRedirectUrl {
    return dotenv.env['MOBILE_REDIRECT_URL'] ?? 'myapp://auth/callback';
  }

  String get supabaseOAuthCallbackUrl {
    return '$supabaseUrl/auth/v1/callback';
  }

  // Get platform-specific redirect URL
  String getRedirectUrl() {
    if (kIsWeb) {
      return webRedirectUrl;
    } else {
      return mobileRedirectUrl;
    }
  }

  // Get all required redirect URLs for OAuth providers
  List<String> getRequiredRedirectUrls() {
    final urls = <String>{
      // Supabase OAuth callback
      supabaseOAuthCallbackUrl,
      
      // Web development URLs
      'http://localhost:3000/auth/callback',
      'http://localhost:5000/auth/callback',
      'http://127.0.0.1:3000/auth/callback',
      'http://127.0.0.1:5000/auth/callback',
      
      // Mobile URLs
      mobileRedirectUrl,
      'com.example.mysalon://auth/callback',
    };
    
    // Add Apple specific URLs
    if (enableAppleOAuth) {
      urls.add(appleRedirectUrl);
    }
    
    // Add production URL if configured
    if (isProduction && dotenv.env['PRODUCTION_REDIRECT_URL'] != null) {
      urls.add(dotenv.env['PRODUCTION_REDIRECT_URL']!);
    }
    
    return urls.toList();
  }

  // ========== OPTIONAL CONFIGURATION ==========
  
  bool get debugMode {
    return dotenv.env['DEBUG'] == 'true' || isDevelopment;
  }

  String get logLevel {
    return dotenv.env['LOG_LEVEL'] ?? (debugMode ? 'debug' : 'info');
  }

  int get apiTimeout {
    return int.tryParse(dotenv.env['API_TIMEOUT'] ?? '30') ?? 30;
  }

  bool get enableAnalytics {
    return dotenv.env['ENABLE_ANALYTICS'] == 'true';
  }

  String? get supportEmail {
    return dotenv.env['SUPPORT_EMAIL'];
  }

  String? get websiteUrl {
    return dotenv.env['WEBSITE_URL'];
  }

  // ========== OAUTH PROVIDER MANAGEMENT ==========
  
  /// 🔥 UPDATED: List of enabled OAuth providers
  List<String> get enabledOAuthProviders {
    final providers = <String>[];
    
    if (enableGoogleOAuth) providers.add('google');
    if (enableFacebookOAuth) providers.add('facebook');
    if (enableAppleOAuth) providers.add('apple'); // 👈 Apple එක add කරන්න
    
    return providers;
  }

  /// 🔥 UPDATED: Check if specific OAuth provider is enabled
  bool isOAuthProviderEnabled(String provider) {
    switch (provider.toLowerCase()) {
      case 'google':
        return enableGoogleOAuth;
      case 'facebook':
        return enableFacebookOAuth;
      case 'apple':  // 👈 Apple support එක
        return enableAppleOAuth;
      default:
        return false;
    }
  }

  /// 🔥 UPDATED: Validate OAuth configuration
  bool hasValidOAuthConfiguration(String provider) {
    switch (provider.toLowerCase()) {
      case 'google':
        return enableGoogleOAuth && 
               googleWebClientId.isNotEmpty && 
               googleWebClientSecret.isNotEmpty &&
               googleWebClientId.endsWith('.apps.googleusercontent.com');
      case 'facebook':
        return enableFacebookOAuth && 
               facebookAppId.isNotEmpty && 
               facebookClientToken.isNotEmpty;
      case 'apple':  // 👈 Apple validation
        return enableAppleOAuth;
      default:
        return false;
    }
  }

  // ========== FEATURE FLAGS ==========
  
  bool get enableBiometrics {
    return dotenv.env['ENABLE_BIOMETRICS'] != 'false';
  }

  bool get enableDarkMode {
    return dotenv.env['ENABLE_DARK_MODE'] != 'false';
  }

  bool get enableNotifications {
    return dotenv.env['ENABLE_NOTIFICATIONS'] != 'false';
  }

  // ========== ENVIRONMENT CHECKS ==========
  
  bool get isProduction => environment == 'production';
  bool get isStaging => environment == 'staging';
  bool get isDevelopment => environment == 'development';
  bool get isTest => environment == 'test';

  // ========== VALIDATION ==========
  
  /// 🔥 UPDATED: Validate with Apple support
  void validate() {
    final errors = <String>[];
    
    // Check required variables
    if (supabaseUrl.isEmpty || supabaseUrl.contains('your-project')) {
      errors.add('SUPABASE_URL is invalid');
    }
    
    if (supabaseAnonKey.isEmpty || supabaseAnonKey.contains('your-anon-key')) {
      errors.add('SUPABASE_ANON_KEY is invalid');
    }
    
    // Check URL format
    if (!supabaseUrl.startsWith('https://')) {
      errors.add('SUPABASE_URL must use HTTPS');
    }
    
    if (!supabaseUrl.contains('supabase.co')) {
      errors.add('SUPABASE_URL must be a valid Supabase URL');
    }
    
    // Validate OAuth configurations if enabled
    if (enableGoogleOAuth) {
      if (googleWebClientId.isEmpty || googleWebClientId.contains('your-client-id')) {
        errors.add('GOOGLE_WEB_CLIENT_ID is invalid');
      }
      if (googleWebClientSecret.isEmpty || googleWebClientSecret.contains('your-client-secret')) {
        errors.add('GOOGLE_WEB_CLIENT_SECRET is invalid');
      }
      if (!googleWebClientId.endsWith('.apps.googleusercontent.com')) {
        errors.add('GOOGLE_WEB_CLIENT_ID must end with .apps.googleusercontent.com');
      }
    }
    
    if (enableFacebookOAuth) {
      if (facebookAppId.isEmpty || facebookAppId.contains('your-app-id')) {
        errors.add('FACEBOOK_APP_ID is invalid');
      }
      if (facebookClientToken.isEmpty || facebookClientToken.contains('your-client-token')) {
        errors.add('FACEBOOK_CLIENT_TOKEN is invalid');
      }
    }
    
    // 👈 Apple validation (optional)
    if (enableAppleOAuth) {
      // Apple doesn't require client ID validation for basic OAuth
      if (appleServiceId.isNotEmpty) {
        print('🍎 Apple Service ID configured: $appleServiceId');
      }
    }
    
    if (errors.isNotEmpty) {
      throw Exception('Environment validation failed:\n${errors.join('\n')}');
    }
  }

  // ========== HELPER METHODS ==========
  
  String _getRequired(String key) {
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw Exception('Required environment variable $key is not set');
    }
    return value;
  }

  String? getOptional(String key) {
    return dotenv.env[key];
  }

  int? getOptionalInt(String key) {
    final value = dotenv.env[key];
    return value != null ? int.tryParse(value) : null;
  }

  bool? getOptionalBool(String key) {
    final value = dotenv.env[key];
    if (value == null) return null;
    return value.toLowerCase() == 'true';
  }

  double? getOptionalDouble(String key) {
    final value = dotenv.env[key];
    return value != null ? double.tryParse(value) : null;
  }

  // ========== DEBUG INFO ==========
  
  /// 🔥 UPDATED: Print info with Apple support
  void printInfo() {
    if (!debugMode) return;
    
    print('\n' + '=' * 60);
    print('🌍 ENVIRONMENT CONFIGURATION');
    print('=' * 60);
    
    // App Info
    print('📱 App: $appName v$appVersion');
    print('🌐 Environment: $environment');
    print('🔧 Debug Mode: $debugMode');
    print('📝 Log Level: $logLevel');
    
    // Supabase Info (partial for security)
    final url = supabaseUrl;
    final displayUrl = url.length > 40 ? '${url.substring(0, 40)}...' : url;
    print('🔗 Supabase URL: $displayUrl');
    print('🔑 Supabase Key: ${supabaseAnonKey.length} chars');
    print('🔗 Supabase OAuth URL: $supabaseOAuthCallbackUrl');
    
    // OAuth Configuration
    print('\n🔐 OAuth Configuration:');
    
    if (enableGoogleOAuth) {
      print('   • Google OAuth: ✅ Enabled');
      final googleId = googleWebClientId;
      final displayGoogleId = googleId.length > 30 ? '${googleId.substring(0, 30)}...' : googleId;
      print('     - Client ID: $displayGoogleId');
      print('     - Valid: ${googleWebClientId.endsWith('.apps.googleusercontent.com') ? '✅' : '❌'}');
    } else {
      print('   • Google OAuth: ❌ Disabled');
    }
    
    if (enableFacebookOAuth) {
      print('   • Facebook OAuth: ✅ Enabled');
      final fbId = facebookAppId;
      final displayFbId = fbId.length > 15 ? '${fbId.substring(0, 15)}...' : fbId;
      print('     - App ID: $displayFbId');
    } else {
      print('   • Facebook OAuth: ❌ Disabled');
    }
    
    // 🔥 Apple status
    if (enableAppleOAuth) {
      print('   • Apple OAuth: ✅ Enabled');
      if (appleServiceId.isNotEmpty) {
        print('     - Service ID: $appleServiceId');
      }
    } else {
      print('   • Apple OAuth: ❌ Disabled');
    }
    
    // Redirect URLs
    print('\n🔄 Redirect URLs:');
    print('   • Web: $webRedirectUrl');
    print('   • Mobile: $mobileRedirectUrl');
    print('   • Supabase: $supabaseOAuthCallbackUrl');
    if (enableAppleOAuth) {
      print('   • Apple: $appleRedirectUrl');
    }
    
    // Feature Flags
    print('\n🚀 Feature Flags:');
    print('   • Biometrics: ${enableBiometrics ? '✅' : '❌'}');
    print('   • Dark Mode: ${enableDarkMode ? '✅' : '❌'}');
    print('   • Notifications: ${enableNotifications ? '✅' : '❌'}');
    print('   • Analytics: ${enableAnalytics ? '✅' : '❌'}');
    
    // Optional Config
    if (supportEmail != null) {
      print('📧 Support: $supportEmail');
    }
    if (websiteUrl != null) {
      print('🌐 Website: $websiteUrl');
    }
    
    // Show non-secret variables in debug mode
    print('\n📋 Environment Variables:');
    print('-' * 30);
    dotenv.env.forEach((key, value) {
      final isSecret = key.contains('KEY') || 
                      key.contains('SECRET') || 
                      key.contains('PASSWORD') ||
                      key.contains('TOKEN') ||
                      key.contains('PRIVATE');
      
      if (!isSecret) {
        print('$key: $value');
      } else if (debugMode && key == 'ENVIRONMENT') {
        print('$key: $value');
      }
    });
    
    print('=' * 60 + '\n');
  }
  
  // ========== OAUTH VALIDATION METHODS ==========
  
  /// 🔥 UPDATED: Validate OAuth configurations with Apple
  Map<String, dynamic> validateOAuthConfigurations() {
    final results = <String, dynamic>{};
    
    // Google OAuth
    results['google'] = {
      'enabled': enableGoogleOAuth,
      'clientId': googleWebClientId.isNotEmpty,
      'clientSecret': googleWebClientSecret.isNotEmpty,
      'validFormat': googleWebClientId.endsWith('.apps.googleusercontent.com'),
      'redirectUrls': getRequiredRedirectUrls(),
    };
    
    // Facebook OAuth
    results['facebook'] = {
      'enabled': enableFacebookOAuth,
      'appId': facebookAppId.isNotEmpty,
      'clientToken': facebookClientToken.isNotEmpty,
      'redirectUrls': getRequiredRedirectUrls(),
    };
    
    // 🔥 Apple OAuth
    results['apple'] = {
      'enabled': enableAppleOAuth,
      'serviceId': appleServiceId.isNotEmpty,
      'redirectUrls': getRequiredRedirectUrls(),
    };
    
    return results;
  }
  
  // Get OAuth provider configuration
  /// 🔥 UPDATED: Get provider config with Apple
  Map<String, dynamic>? getOAuthProviderConfig(String provider) {
    switch (provider.toLowerCase()) {
      case 'google':
        return {
          'clientId': googleWebClientId,
          'clientSecret': googleWebClientSecret,
          'androidClientId': googleAndroidClientId,
          'iosClientId': googleIosClientId,
          'enabled': enableGoogleOAuth,
        };
      case 'facebook':
        return {
          'appId': facebookAppId,
          'clientToken': facebookClientToken,
          'enabled': enableFacebookOAuth,
        };
      case 'apple':  // 👈 Apple config
        return {
          'serviceId': appleServiceId,
          'redirectUrl': appleRedirectUrl,
          'enabled': enableAppleOAuth,
        };
      default:
        return null;
    }
  }
}