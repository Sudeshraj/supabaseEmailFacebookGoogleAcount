import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

class AppVersion {
  static String version = '1.0.0+1';
  static String buildType = 'debug';
  static String name = '';

  static Future<void> init() async {
    try {
      final info = await PackageInfo.fromPlatform();
      name = info.appName;
      // Auto detect build type
      if (kReleaseMode) {
        buildType = 'production';
        version = '${info.version}+${info.buildNumber}';
      } else if (kProfileMode) {
        buildType = 'staging';
        version = '${info.version}+${info.buildNumber}-staging';
      } else {
        buildType = 'debug';
        version = '${info.version}+${info.buildNumber}-dev';
      }
      
     
    } catch (e) {
      version = '1.0.0+1';
    }
  }

  static String getDisplayVersion() => version;
  static bool isProduction() => buildType == 'production';
  static bool isStaging() => buildType == 'staging';
  static bool isDebug() => buildType == 'debug';
}

// 1.0.0+1 = version + build number
// pubspec.yaml eke change karama thamai version,build numbers change venne build ekak dammata change venne na
// playstore valata ganne pubspec eke version numbers ekai app eke ekai samana venna thamai mehema ganne, hard code nokara