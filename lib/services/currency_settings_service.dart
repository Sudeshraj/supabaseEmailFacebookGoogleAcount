import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'currency_service.dart';
import 'timezone_service.dart';

class CurrencySettingsService {
  CurrencySettingsService._();
  static final CurrencySettingsService instance = CurrencySettingsService._();

  final _supabase = Supabase.instance.client;
  final _currencyService = CurrencyService.instance;

  static const List<String> supportedCurrencies = [
    'LKR', 'USD', 'INR', 'GBP', 'EUR',
    'AUD', 'AED', 'CAD', 'JPY', 'SGD', 'MYR',
    'NZD',
  ];

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

  // ✅ NEW: Get exchange rate for display
  Future<double?> getExchangeRate({
    required String fromCurrency,
    required String toCurrency,
  }) async {
    if (fromCurrency == toCurrency) return 1.0;
    try {
      final result = await _supabase.rpc(
        'get_exchange_rate',
        params: {
          'p_from_currency': fromCurrency,
          'p_to_currency': toCurrency,
        },
      );
      if (result == null) return null;
      final rate = (result as num).toDouble();
      return rate > 0 ? rate : null;
    } catch (e) {
      debugPrint('❌ getExchangeRate: $e');
      return null;
    }
  }
}