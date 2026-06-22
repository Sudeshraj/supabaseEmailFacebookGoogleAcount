import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path;

class ProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ✅ Get current user profile
  Future<Map<String, dynamic>?> getProfile(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('''
            id,
            email,
            full_name,
            phone,
            avatar_url,
            bio,
            address,
            city,
            is_active,
            created_at,
            updated_at
          ''')
          .eq('id', userId)
          .maybeSingle();
      return response;
    } catch (e) {    
      return null;
    }
  }

  // Update profile
  Future<bool> updateProfile({
    required String userId,
    String? fullName,
    String? phone,
    String? bio,
    String? address,
    String? city,
    String? avatarUrl,
  }) async {
    try {
      final Map<String, dynamic> updates = {};
      if (fullName != null) updates['full_name'] = fullName;
      if (phone != null) updates['phone'] = phone;
      if (bio != null) updates['bio'] = bio;
      if (address != null) updates['address'] = address;
      if (city != null) updates['city'] = city;
      if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
      updates['updated_at'] = DateTime.now().toIso8601String();

      await _supabase.from('profiles').update(updates).eq('id', userId);
      return true;
    } catch (e) {    
      return false;
    }
  }

  //  UPLOAD PROFILE IMAGE - CROSS PLATFORM
  Future<String?> uploadProfileImage({
    required String userId,
    required dynamic imageFile,  // File (mobile) or Uint8List (web)
    String? fileName,
  }) async {
    try {     
      //  Determine file name
      String finalFileName;
      if (fileName != null) {
        finalFileName = fileName;
      } else if (imageFile is File) {
        final extension = path.extension(imageFile.path);
        finalFileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}$extension';
      } else {
        finalFileName = '${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      }
      
      final filePath = 'profiles/$finalFileName';
    

      // Upload based on platform
      if (kIsWeb) {
        // Web: Upload bytes directly
        if (imageFile is! Uint8List) {
          throw Exception('Web upload requires Uint8List');
        }
        await _supabase.storage
            .from('profiles')
            .uploadBinary(filePath, imageFile);
      } else {
        // Mobile: Upload File
        if (imageFile is! File) {
          throw Exception('Mobile upload requires File');
        }
        // Check file size (max 5MB)
        final fileSize = await imageFile.length();      
        
        if (fileSize > 5 * 1024 * 1024) {
          throw Exception('Image must be less than 5MB');
        }
        
        await _supabase.storage
            .from('profiles')
            .upload(filePath, imageFile);
      }     
    

      //  Get public URL
      final publicUrl = _supabase.storage
          .from('profiles')
          .getPublicUrl(filePath);      
     

      // Update profile with new image URL
      await _supabase
          .from('profiles')
          .update({
            'avatar_url': publicUrl,
            'updated_at': DateTime.now().toIso8601String()
          })
          .eq('id', userId);      
   
      return publicUrl;
      
    } catch (e) {    
      rethrow;
    }
  }

  // Delete old profile image
  Future<void> deleteOldImage(String imageUrl) async {
    try {
           
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.path.split('/');
      final fileName = pathSegments.last;
      
      if (fileName.isNotEmpty) {
        final filePath = 'profiles/$fileName';
        await _supabase.storage
            .from('profiles')
            .remove([filePath]);       
      }
    } catch (e) {
      debugPrint('⚠️ Could not delete old image: $e');
    }
  }

  // Get ALL user roles
  Future<List<String>> getUserRoles(String userId) async {
    try {
      final response = await _supabase
          .from('user_roles')
          .select('roles!inner(name)')
          .eq('user_id', userId);

      List<String> roles = [];
      for (var item in response) {
        if (item['roles'] != null && item['roles']['name'] != null) {
          roles.add(item['roles']['name'] as String);
        }
      }
      return roles;
    } catch (e) {     
      return [];
    }
  }

  // ✅ Get role icon
  String getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'customer': return '👤';
      case 'barber': return '✂️';
      case 'owner': return '🏢';
      default: return '👤';
    }
  }

  // ✅ Get role color
  Color getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'customer': return Colors.blue;
      case 'barber': return Colors.purple;
      case 'owner': return Colors.orange;
      default: return Colors.grey;
    }
  }

  // ✅ Get role display name
  String getRoleDisplayName(String role) {
    switch (role.toLowerCase()) {
      case 'customer': return 'Customer';
      case 'barber': return 'Barber';
      case 'owner': return 'Salon Owner';
      default: return role;
    }
  }
}