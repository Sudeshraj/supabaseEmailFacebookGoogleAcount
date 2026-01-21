// services/supabase_persistence.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabasePersistenceHelper {
  // Check if there's a persisted session
  static Future<bool> hasPersistedSession() async {
    try {
      final supabase = Supabase.instance.client;
      
      // Check if there's any user data
      final currentUser = supabase.auth.currentUser;
      final currentSession = supabase.auth.currentSession;
      
      print('🔍 Persistence Check:');
      print('   - Current user: ${currentUser?.email ?? "None"}');
      print('   - Current session: ${currentSession != null ? "Exists" : "None"}');
      print('   - Session expiry: ${currentSession?.expiresAt != null ? DateTime.fromMillisecondsSinceEpoch(currentSession!.expiresAt!).toString() : "No expiry"}');
      
      return currentSession != null;
    } catch (e) {
      print('❌ Error checking persistence: $e');
      return false;
    }
  }

  // Debug session persistence
  static Future<void> debugSessionPersistence() async {
    print('🔍 ==== SESSION PERSISTENCE DEBUG ====');
    
    try {
      final supabase = Supabase.instance.client;
      
      print('1. Current Auth State:');
      print('   - User: ${supabase.auth.currentUser?.email ?? "No user"}');
      print('   - User ID: ${supabase.auth.currentUser?.id ?? "No ID"}');
      print('   - Session exists: ${supabase.auth.currentSession != null}');
      
      if (supabase.auth.currentSession != null) {
        final session = supabase.auth.currentSession!;
        print('   - Session expiry: ${DateTime.fromMillisecondsSinceEpoch(session.expiresAt!)}');
        print('   - Session token: ${session.accessToken.substring(0, 20)}...');
      }
      
      print('2. Storage Check:');
      // You can add storage checks if using secure storage
      
      print('3. Auto-login readiness:');
      final hasUser = supabase.auth.currentUser != null;
      final hasSession = supabase.auth.currentSession != null;
      final sessionValid = hasSession && _isSessionValid(supabase.auth.currentSession);
      
      print('   - Has user: $hasUser');
      print('   - Has session: $hasSession');
      print('   - Session valid: $sessionValid');
      
    } catch (e) {
      print('❌ Debug error: $e');
    }
    
    print('🔍 ==== DEBUG COMPLETE ====');
  }
  
  static bool _isSessionValid(Session? session) {
    if (session == null) return false;
    if (session.expiresAt == null) return true;
    
    final expiryTime = DateTime.fromMillisecondsSinceEpoch(session.expiresAt!);
    final now = DateTime.now();
    final timeUntilExpiry = expiryTime.difference(now);
    
    return timeUntilExpiry.inMinutes > 2;
  }
}