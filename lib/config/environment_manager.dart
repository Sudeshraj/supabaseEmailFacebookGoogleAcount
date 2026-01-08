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
      // print('✅ Loaded environment: $flavor from $envFile');
    } catch (e) {
      // Fallback to default .env
      try {
        await dotenv.load(fileName: '.env');
        // print('⚠️  Using default .env file');
      } catch (e2) {
        throw Exception('Failed to load any environment file');
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
    return dotenv.env['APP_NAME'] ?? 'AutoLogin App';
  }

  String get appVersion {
    return dotenv.env['APP_VERSION'] ?? '1.0.0';
  }

  String get environment {
    return dotenv.env['ENVIRONMENT'] ?? 'development';
  }

  // ========== OPTIONAL CONFIGURATION ==========
  
  bool get debugMode {
    return dotenv.env['DEBUG'] == 'true';
  }

  String get logLevel {
    return dotenv.env['LOG_LEVEL'] ?? 'info';
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
    
    if (errors.isNotEmpty) {
      throw Exception('Environment validation failed: ${errors.join(', ')}');
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

  // ========== DEBUG INFO ==========
  
  void printInfo() {
    // print('\n' + '=' * 60);
    // print('🌍 ENVIRONMENT CONFIGURATION');
    // print('=' * 60);
    
    // // App Info
    // print('📱 App: $appName v$appVersion');
    // print('🌐 Environment: $environment');
    // print('🔧 Debug Mode: $debugMode');
    // print('📝 Log Level: $logLevel');
    
    // // Supabase Info (partial for security)
    // final url = supabaseUrl;
    // final displayUrl = url.length > 40 ? '${url.substring(0, 40)}...' : url;
    // print('🔗 Supabase URL: $displayUrl');
    // print('🔑 Supabase Key: ${supabaseAnonKey.length} chars');
    
    // // Feature Flags
    // print('\n🚀 Feature Flags:');
    // print('   • Biometrics: ${enableBiometrics ? '✅' : '❌'}');
    // print('   • Dark Mode: ${enableDarkMode ? '✅' : '❌'}');
    // print('   • Notifications: ${enableNotifications ? '✅' : '❌'}');
    // print('   • Analytics: ${enableAnalytics ? '✅' : '❌'}');
    
    // Optional Config
    if (supportEmail != null) {
      // print('📧 Support: $supportEmail');
    }
    if (websiteUrl != null) {
      // print('🌐 Website: $websiteUrl');
    }
    
    // Show all variables in debug mode
    if (debugMode) {
    //   print('\n📋 All Environment Variables:');
    //   print('-' * 30);
    //   dotenv.env.forEach((key, value) {
    //     final isSecret = key.contains('KEY') || 
    //                     key.contains('SECRET') || 
    //                     key.contains('PASSWORD') ||
    //                     key.contains('TOKEN');
        
    //     if (isSecret) {
    //       print('$key: [HIDDEN - ${value.length} chars]');
    //     } else {
    //       print('$key: $value');
    //     }
    //   });
    }
    
    // print('=' * 60 + '\n');
  }
}