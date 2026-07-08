// services/auth_provider_service.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthProviderService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// ✅ Get user's auth providers
  Future<List<Map<String, dynamic>>> getUserAuthProviders() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return [];

      final identities = user.identities ?? [];
      
      List<Map<String, dynamic>> providers = [];
      
      for (var identity in identities) {
        // ✅ Use properties directly
        final provider = identity.provider;
        final providerId = identity.id;
        
        // ✅ Handle createdAt correctly - it might be String or DateTime
        String? createdAtStr;
        if (identity.createdAt != null) {
          if (identity.createdAt is DateTime) {
            createdAtStr = (identity.createdAt as DateTime).toIso8601String();
          } else if (identity.createdAt is String) {
            createdAtStr = identity.createdAt as String;
          } else {
            createdAtStr = identity.createdAt.toString();
          }
        }
        
        providers.add({
          'provider': provider,
          'provider_id': providerId,
          'is_email_password': provider == 'email',
          'is_oauth': provider != 'email',
          'display_name': _getProviderDisplayName(provider),
          'icon': _getProviderIcon(provider),
          'color': _getProviderColor(provider),
          'created_at': createdAtStr,
          'identity': identity, // ✅ Store reference for unlinking
        });
      }
      
      // ✅ If no identities, check if email/password user
      if (providers.isEmpty && user.email != null) {
        providers.add({
          'provider': 'email',
          'provider_id': user.id,
          'is_email_password': true,
          'is_oauth': false,
          'display_name': 'Email & Password',
          'icon': Icons.email_outlined,
          'color': Colors.blue,
          'created_at': user.createdAt,
          'identity': null,
        });
      }
      
      return providers;
    } catch (e) {
      debugPrint('❌ Error getting auth providers: $e');
      return [];
    }
  }

  /// ✅ Check if user has email/password authentication
  Future<bool> hasEmailPasswordAuth() async {
    final providers = await getUserAuthProviders();
    return providers.any((p) => p['is_email_password'] == true);
  }

  /// ✅ Check if user has OAuth providers
  Future<bool> hasOAuthAuth() async {
    final providers = await getUserAuthProviders();
    return providers.any((p) => p['is_oauth'] == true);
  }

  /// ✅ Get primary auth provider
  Future<String?> getPrimaryAuthProvider() async {
    final providers = await getUserAuthProviders();
    if (providers.isEmpty) return null;
    
    for (var p in providers) {
      if (p['is_email_password'] == true) return 'email';
    }
    return providers.first['provider'] as String?;
  }

  /// ✅ Change password
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      // ✅ Verify current password
      try {
        await _supabase.auth.signInWithPassword(
          email: user.email!,
          password: currentPassword,
        );
      } catch (e) {
        throw Exception('Current password is incorrect');
      }

      // ✅ Update password
      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );

      debugPrint('✅ Password changed successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Error changing password: $e');
      rethrow;
    }
  }

  /// ✅ Unlink OAuth provider
  Future<bool> unlinkProvider(String provider) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return false;

      final identities = user.identities ?? [];
      
      // ✅ Find the identity directly
      UserIdentity? identityToRemove;
      
      for (var identity in identities) {
        // ✅ Use .provider property
        if (identity.provider == provider) {
          identityToRemove = identity;
          break;
        }
      }

      if (identityToRemove == null) {
        debugPrint('⚠️ Provider not found: $provider');
        return false;
      }

      // ✅ Unlink using UserIdentity object directly
      await _supabase.auth.unlinkIdentity(identityToRemove);
      
      debugPrint('✅ Unlinked provider: $provider');
      return true;
    } catch (e) {
      debugPrint('❌ Error unlinking provider: $e');
      return false;
    }
  }

  /// ✅ Link new OAuth provider
  Future<bool> linkProvider(String provider) async {
    try {
      // ✅ Redirect URL for linking
      final redirectUrl = 'myapp://auth-callback';
      
      await _supabase.auth.signInWithOAuth(
        _getOAuthProvider(provider),
        redirectTo: redirectUrl,
      );
      
      return true;
    } catch (e) {
      debugPrint('❌ Error linking provider: $e');
      return false;
    }
  }

  /// ✅ Get provider display name
  String _getProviderDisplayName(String provider) {
    switch (provider) {
      case 'email': return 'Email & Password';
      case 'google': return 'Google';
      case 'facebook': return 'Facebook';
      case 'apple': return 'Apple';
      default: return provider;
    }
  }

  /// ✅ Get provider icon
  IconData _getProviderIcon(String provider) {
    switch (provider) {
      case 'email': return Icons.email_outlined;
      case 'google': return Icons.g_mobiledata;
      case 'facebook': return Icons.facebook;
      case 'apple': return Icons.apple;
      default: return Icons.person_outline;
    }
  }

  /// ✅ Get provider color
  Color _getProviderColor(String provider) {
    switch (provider) {
      case 'email': return Colors.blue;
      case 'google': return const Color(0xFFDB4437);
      case 'facebook': return const Color(0xFF1877F2);
      case 'apple': return Colors.black;
      default: return Colors.grey;
    }
  }

  /// ✅ Get OAuth provider
  OAuthProvider _getOAuthProvider(String provider) {
    switch (provider) {
      case 'google': return OAuthProvider.google;
      case 'facebook': return OAuthProvider.facebook;
      case 'apple': return OAuthProvider.apple;
      default: throw Exception('Unsupported provider: $provider');
    }
  }
}