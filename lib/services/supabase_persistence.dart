// services/supabase_persistence.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabasePersistenceHelper {
  // Check if there's a persisted session
  static Future<bool> hasPersistedSession() async {
    try {
      final supabase = Supabase.instance.client;      
      // Check if there's any user data
      final currentSession = supabase.auth.currentSession;      
      debugPrint('🔍 Persistence Check:');  
      
      return currentSession != null;
    } catch (e) {
      debugPrint('Error checking persistence: $e');
      return false;
    }
  }
  
}