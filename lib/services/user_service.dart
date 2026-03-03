// lib/services/user_service.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // ⚡ 1. User Login එක record කරන්න
  Future<void> recordUserLogin(String userId, int roleId) async {
    try {
      await _supabase.rpc('record_user_login', params: {
        'user_id': userId,
        'user_role_id': roleId,
      });
      debugPrint('Login recorded successfully');
    } on PostgrestException catch (error) {
      debugPrint('PostgreSQL Error: ${error.message}');
      rethrow;
    } catch (error) {
      debugPrint('Error recording login: $error');
      rethrow;
    }
  }
  
  // ⚡ 2. User Activity එක record කරන්න
  Future<void> recordUserActivity(String userId, int roleId) async {
    try {
      await _supabase.rpc('record_user_activity', params: {
        'user_id': userId,
        'user_role_id': roleId,
      });
    } catch (error) {
      debugPrint('Error recording activity: $error');
    }
  }
  
  // ⚡ 3. Online Users ගන්න
  Future<List<Map<String, dynamic>>> getOnlineUsers() async {
    try {
      final response = await _supabase.rpc('get_online_users');
      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      debugPrint('Error getting online users: $error');
      return [];
    }
  }
  
  // ⚡ 4. User ගෙ Role එක Check කරන්න
  Future<bool> hasRole(String userId, String roleName) async {
    try {
      final response = await _supabase.rpc('has_role', params: {
        'user_id': userId,
        'role_name': roleName,
      });
      return response as bool;
    } catch (error) {
      debugPrint('Error checking role: $error');
      return false;
    }
  }
  
  // ⚡ 5. User ගෙ Roles ගන්න
  Future<List<Map<String, dynamic>>> getUserRoles(String userId) async {
    try {
      final response = await _supabase.rpc('get_user_roles', params: {
        'user_id': userId,
      });
      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      debugPrint('Error getting user roles: $error');
      return [];
    }
  }
  
  // ⚡ 6. User Login Info ගන්න
  Future<Map<String, dynamic>?> getUserLoginInfo(String userId, int roleId) async {
    try {
      final response = await _supabase.rpc('get_user_login_info', params: {
        'user_id': userId,
        'user_role_id': roleId,
      });
      
      if (response != null && response.isNotEmpty) {
        return Map<String, dynamic>.from(response[0]);
      }
      return null;
    } catch (error) {
      debugPrint('Error getting login info: $error');
      return null;
    }
  }
  
  // ⚡ 7. User Logout එක record කරන්න
  Future<void> recordUserLogout(String userId, int roleId) async {
    try {
      await _supabase.rpc('record_user_logout', params: {
        'user_id': userId,
        'user_role_id': roleId,
      });
    } catch (error) {
      debugPrint('Error recording logout: $error');
    }
  }
}