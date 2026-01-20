import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Custom persistence handler for Supabase
class SupabasePersistenceHelper {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  
  /// Check if we have a persisted session
  static Future<bool> hasPersistedSession() async {
    try {
      final token = await _secureStorage.read(key: 'supabase.auth.token');
      return token != null && token.isNotEmpty;
    } catch (e) {
      print('❌ Error checking persisted session: $e');
      return false;
    }
  }
  
  /// Get persisted session data
  static Future<String?> getPersistedSession() async {
    try {
      return await _secureStorage.read(key: 'supabase.auth.token');
    } catch (e) {
      print('❌ Error getting persisted session: $e');
      return null;
    }
  }
  
  /// Clear persisted session
  static Future<void> clearPersistedSession() async {
    try {
      await _secureStorage.delete(key: 'supabase.auth.token');
      print('✅ Persisted session cleared');
    } catch (e) {
      print('❌ Error clearing persisted session: $e');
    }
  }
  
  /// Force session persistence (for debugging)
  static Future<void> debugSessionPersistence() async {
    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      final user = supabase.auth.currentUser;
      
      print('🔍 DEBUG SESSION PERSISTENCE:');
      print('   - Current user: ${user?.email}');
      print('   - Has session: ${session != null}');
      print('   - Session expiry: ${session?.expiresAt}');
      
      // Check what's in secure storage
      final storedToken = await _secureStorage.read(key: 'supabase.auth.token');
      print('   - Stored token exists: ${storedToken != null}');
      print('   - Stored token length: ${storedToken?.length}');
      
    } catch (e) {
      print('❌ Debug error: $e');
    }
  }
}