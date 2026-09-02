import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfileService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // ============================================================
  // ✅ PROFILE CRUD OPERATIONS
  // ============================================================

  /// ✅ Get current user profile
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
            is_blocked,
            extra_data,
            created_at,
            updated_at
          ''')
          .eq('id', userId)
          .maybeSingle();
      return response;
    } catch (e) {
      debugPrint('❌ Error getting profile: $e');
      return null;
    }
  }

  /// ✅ Update profile
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
      // ✅ avatar_url එක අපේම Supabase storage domain එකෙන්ම ආවේද කියලා validate කරනවා.
      // Data-tampering/phishing risk එකක් වළක්වනවා - RLS එකෙන් check කරන්නේ
      // "auth.uid() = id" විතරයි, URL format එක check කරන්නේ නෑ.
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        final supabaseUrl = _supabase.storage.from('profiles').getPublicUrl('');
        final expectedHost = Uri.parse(supabaseUrl).host;
        final providedHost = Uri.tryParse(avatarUrl)?.host;

        if (providedHost != expectedHost) {
          debugPrint('❌ Rejected invalid avatar_url host: $providedHost');
          return false;
        }
      }

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
      debugPrint('❌ Error updating profile: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ PROFILE IMAGE UPLOAD
  // ============================================================

  /// ✅ Upload profile image - expects already-compressed bytes.
  /// Compression (resize + quality reduction) happens upstream, in
  /// profile_screen.dart, right after the image is picked - see
  /// compressAvatarBytes() in utils/image_compression.dart. By the time
  /// this runs, `imageFile` is always a Uint8List on every platform, so
  /// there's no need to branch on kIsWeb / File vs Uint8List here anymore.
  /// The path is fixed ('$userId/avatar.jpg') with upsert:true, so every
  /// re-upload REPLACES the previous image instead of creating an orphan.
  Future<String?> uploadProfileImage({
    required String userId,
    required dynamic imageFile, // always Uint8List (compressed) by this point
    String? fileName, // kept for backward compatibility, not used
  }) async {
    try {
      if (imageFile is! Uint8List) {
        throw Exception('Expected compressed image bytes (Uint8List)');
      }

      // Safety net - compression should already keep this well under 5MB,
      // but guard anyway in case compression silently fell back to the
      // original bytes on an unsupported platform.
      if (imageFile.lengthInBytes > 5 * 1024 * 1024) {
        throw Exception('Image must be less than 5MB');
      }

      // ✅ Fixed filename + fixed extension - always the same path
      const finalFileName = 'avatar.jpg';
      final filePath = '$userId/$finalFileName';

      await _supabase.storage
          .from('profiles')
          .uploadBinary(
            filePath,
            imageFile,
            fileOptions: const FileOptions(
              upsert: true, // ✅ replace old image at the same path
              contentType: 'image/jpeg',
            ),
          );

      // Get public URL
      // ✅ Same path every time -> append a cache-busting query param
      // so the CDN/browser doesn't keep showing the old cached image.
      final baseUrl = _supabase.storage
          .from('profiles')
          .getPublicUrl(filePath);
      final publicUrl = '$baseUrl?t=${DateTime.now().millisecondsSinceEpoch}';

      // Update profile with new image URL
      await _supabase
          .from('profiles')
          .update({
            'avatar_url': publicUrl,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      return publicUrl;
    } catch (e) {
      debugPrint('❌ Error uploading image: $e');
      rethrow;
    }
  }

  /// ✅ Delete old profile image
  Future<void> deleteOldImage(String imageUrl) async {
    try {
      // Strip query params (?t=...) - only need the path portion
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.path.split('/');

      // Public URL structure: .../storage/v1/object/public/profiles/userId/avatar.jpg
      // Find the bucket name ('profiles') and take everything after it
      // (userId/avatar.jpg) as the storage path.
      final bucketIndex = pathSegments.indexOf('profiles');

      if (bucketIndex == -1 || bucketIndex + 1 >= pathSegments.length) {
        debugPrint('⚠️ Could not parse storage path from URL: $imageUrl');
        return;
      }

      final filePath = pathSegments.sublist(bucketIndex + 1).join('/');

      if (filePath.isNotEmpty) {
        await _supabase.storage.from('profiles').remove([filePath]);
        debugPrint('✅ Deleted old image: $filePath');
      }
    } catch (e) {
      debugPrint('⚠️ Could not delete old image: $e');
    }
  }

  // ============================================================
  // ✅ USER ROLES - UPDATED WITH STATUS
  // ============================================================

  /// ✅ Get ACTIVE user roles only (status = 'active')
  Future<List<String>> getUserRoles(String userId) async {
    try {
      final response = await _supabase
          .from('user_roles')
          .select('''
            roles!inner(name),
            status
          ''')
          .eq('user_id', userId)
          .eq('status', 'active'); // ✅ Only active roles

      List<String> roles = [];
      for (var item in response) {
        if (item['roles'] != null && item['roles']['name'] != null) {
          roles.add(item['roles']['name'] as String);
        }
      }
      return roles;
    } catch (e) {
      debugPrint('❌ Error getting user roles: $e');
      return [];
    }
  }

  /// ✅ Get ALL user roles with status (including inactive, scheduled_for_deletion)
  Future<List<Map<String, dynamic>>> getAllUserRolesWithStatus(
    String userId,
  ) async {
    try {
      final response = await _supabase
          .from('user_roles')
          .select('''
            roles!inner(name),
            status,
            role_id,
            created_at,
            updated_at
          ''')
          .eq('user_id', userId);

      List<Map<String, dynamic>> roles = [];
      for (var item in response) {
        if (item['roles'] != null && item['roles']['name'] != null) {
          roles.add({
            'role': item['roles']['name'] as String,
            'status': item['status'] as String? ?? 'active',
            'role_id': item['role_id'],
            'created_at': item['created_at'],
            'updated_at': item['updated_at'],
          });
        }
      }
      return roles;
    } catch (e) {
      debugPrint('❌ Error getting all roles: $e');
      return [];
    }
  }

  /// ✅ Get status of a specific role
  Future<String?> getUserRoleStatus({
    required String userId,
    required String role,
  }) async {
    try {
      final response = await _supabase
          .from('user_roles')
          .select('status')
          .eq('user_id', userId)
          .eq('roles.name', role)
          .maybeSingle();

      if (response != null) {
        return response['status'] as String? ?? 'active';
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting role status: $e');
      return null;
    }
  }

  /// ✅ Update role status
  Future<bool> updateUserRoleStatus({
    required String userId,
    required String role,
    required String
    status, // 'active', 'inactive', 'scheduled_for_deletion', 'deleted'
    int gracePeriodDays = 90,
  }) async {
    try {
      final response = await _supabase.rpc(
        'update_role_status',
        params: {
          'p_user_id': userId,
          'p_role': role,
          'p_status': status,
          'p_grace_period_days': gracePeriodDays,
        },
      );

      final success = response['success'] as bool? ?? false;

      if (success) {
        debugPrint('✅ Role status updated: $role -> $status');
      } else {
        debugPrint('❌ Failed to update role status: ${response['message']}');
      }

      return success;
    } catch (e) {
      debugPrint('❌ Error updating role status: $e');
      return false;
    }
  }

  /// ✅ Check if user has any active roles
  Future<bool> hasActiveRoles(String userId) async {
    try {
      final response = await _supabase
          .from('user_roles')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'active')
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('❌ Error checking active roles: $e');
      return false;
    }
  }

  /// ✅ Get count of active roles
  Future<int> getActiveRolesCount(String userId) async {
    try {
      final response = await _supabase
          .from('user_roles')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'active');

      // ✅ Simply return the length of the response list
      return response.length;
    } catch (e) {
      debugPrint('❌ Error getting active roles count: $e');
      return 0;
    }
  }

  /// ✅ Check if user has a specific role with active status
  Future<bool> hasActiveRole({
    required String userId,
    required String role,
  }) async {
    try {
      final response = await _supabase
          .from('user_roles')
          .select('id')
          .eq('user_id', userId)
          .eq('roles.name', role)
          .eq('status', 'active')
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('❌ Error checking active role: $e');
      return false;
    }
  }

  /// ✅ Check if user has any scheduled_for_deletion roles
  Future<bool> hasScheduledRoles(String userId) async {
    try {
      final response = await _supabase
          .from('user_roles')
          .select('id')
          .eq('user_id', userId)
          .eq('status', 'scheduled_for_deletion')
          .maybeSingle();

      return response != null;
    } catch (e) {
      debugPrint('❌ Error checking scheduled roles: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ PROFILE LEVEL STATUS - NEW
  // ============================================================

  /// ✅ Get profile level status
  Future<String?> getProfileLevelStatus(String userId) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('extra_data')
          .eq('id', userId)
          .maybeSingle();

      if (response != null) {
        final extraData =
            response['extra_data'] as Map<String, dynamic>? ?? {};
        final profileStatus =
            extraData['profile_status'] as Map<String, dynamic>?;
        if (profileStatus != null) {
          return profileStatus['status'] as String? ?? 'active';
        }
      }
      return 'active';
    } catch (e) {
      debugPrint('❌ Error getting profile level status: $e');
      return null;
    }
  }

  /// ✅ Update profile level status
  Future<bool> updateProfileLevelStatus({
    required String userId,
    required String status,
    int gracePeriodDays = 90,
  }) async {
    try {
      final response = await _supabase.rpc(
        'update_profile_level_status',
        params: {
          'p_user_id': userId,
          'p_status': status,
          'p_grace_period_days': gracePeriodDays,
        },
      );

      final success = response['success'] as bool? ?? false;

      if (success) {
        debugPrint('✅ Profile level status updated: $status');
      }

      return success;
    } catch (e) {
      debugPrint('❌ Error updating profile level status: $e');
      return false;
    }
  }

  // ============================================================
  // ✅ HELPER METHODS
  // ============================================================

  /// ✅ Get role icon
  String getRoleIcon(String role) {
    switch (role.toLowerCase()) {
      case 'customer':
        return '👤';
      case 'barber':
        return '✂️';
      case 'owner':
        return '🏢';
      default:
        return '👤';
    }
  }

  /// ✅ Get role color
  Color getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'customer':
        return Colors.blue;
      case 'barber':
        return Colors.purple;
      case 'owner':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// ✅ Get role display name
  String getRoleDisplayName(String role) {
    switch (role.toLowerCase()) {
      case 'customer':
        return 'Customer';
      case 'barber':
        return 'Barber';
      case 'owner':
        return 'Salon Owner';
      default:
        return role;
    }
  }

  /// ✅ Get role status display text
  String getRoleStatusDisplay(String status) {
    switch (status) {
      case 'active':
        return 'Active ✅';
      case 'inactive':
        return 'Inactive ⏸️';
      case 'scheduled_for_deletion':
        return 'Scheduled for Deletion ⏳';
      case 'deleted':
        return 'Deleted 🗑️';
      default:
        return status;
    }
  }

  /// ✅ Get role status color
  Color getRoleStatusColor(String status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.orange;
      case 'scheduled_for_deletion':
        return Colors.red.shade300;
      case 'deleted':
        return Colors.red.shade700;
      default:
        return Colors.grey;
    }
  }
}