import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'currency_service.dart';
import 'timezone_service.dart';

/// ✅ Manages user's preferred currency (source of truth: profiles.preferred_currency)
class CurrencySettingsService {
  CurrencySettingsService._();
  static final CurrencySettingsService instance = CurrencySettingsService._();

  final _supabase = Supabase.instance.client;
  final _currencyService = CurrencyService.instance;

  static const List<String> supportedCurrencies = [
    'LKR', 'USD', 'INR', 'GBP', 'EUR',
    'AUD', 'AED', 'CAD', 'JPY', 'SGD', 'MYR','NZD',
  ];

  /// Get current user's preferred currency
  Future<String> getUserCurrency() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return _defaultCurrencyFromTimezone();

      final profile = await _supabase
          .from('profiles')
          .select('preferred_currency')
          .eq('id', userId)
          .maybeSingle();

      final dbCurrency = profile?['preferred_currency'] as String?;
      if (dbCurrency != null && dbCurrency.isNotEmpty) {
        return dbCurrency;
      }

      return _defaultCurrencyFromTimezone();
    } catch (e) {
      debugPrint('❌ getUserCurrency: $e');
      return _defaultCurrencyFromTimezone();
    }
  }

  /// Update user's preferred currency
  Future<bool> updateUserCurrency(String currency) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final normalized = currency.toUpperCase();
      if (!supportedCurrencies.contains(normalized)) return false;

      await _supabase.from('profiles').update({
        'preferred_currency': normalized,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      debugPrint('✅ Currency updated to: $normalized');
      return true;
    } catch (e) {
      debugPrint('❌ updateUserCurrency: $e');
      return false;
    }
  }

  String _defaultCurrencyFromTimezone() {
    try {
      final tz = TimezoneService.getCurrentTimezone();
      return TimezoneService.getCurrencyForTimezone(tz);
    } catch (_) {
      return 'LKR';
    }
  }

  String getSymbol(String currency) =>
      _currencyService.getSymbol(currency);
}