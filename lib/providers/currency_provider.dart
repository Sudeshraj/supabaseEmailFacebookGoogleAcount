import 'package:flutter/material.dart';
import '../services/currency_service.dart';

class CurrencyProvider extends ChangeNotifier {
  final CurrencyService _service = CurrencyService.instance;

  // ============================================
  // STATE
  // ============================================
  String _salonCurrencyCode = 'LKR';
  String _userCurrencyCode = 'LKR'; // Future use සඳහා
  int? _currentSalonId;

  // ============================================
  // GETTERS
  // ============================================
  String get salonCurrencyCode => _salonCurrencyCode;
  String get userCurrencyCode => _userCurrencyCode;
  String get salonSymbol => _service.getSymbol(_salonCurrencyCode);
  IconData get salonIcon => _service.getIcon(_salonCurrencyCode);
  CurrencyInfo get salonInfo => _service.getInfo(_salonCurrencyCode);
  bool get isSameCurrency => _service.isSame(_salonCurrencyCode, _userCurrencyCode);

  // ============================================
  // ACTIONS
  // ============================================
  
  /// Salon එකකට switch කරනකොට call කරන්න
  void setSalon({
    required int salonId,
    required String currencyCode,
  }) {
    // එකම salon එක නම් skip කරන්න
    if (_currentSalonId == salonId && _salonCurrencyCode == currencyCode) {
      return;
    }

    _currentSalonId = salonId;
    _salonCurrencyCode = currencyCode;
    notifyListeners();
  }

  /// User ගේ currency එක set කරන්න (future)
  void setUserCurrency(String currencyCode) {
    if (_userCurrencyCode == currencyCode) return;
    _userCurrencyCode = currencyCode;
    notifyListeners();
  }

  // ============================================
  // HELPERS (Provider එකෙන් කෙලින්ම call කරන්න පුළුවන්)
  // ============================================
  String formatPrice(dynamic price, {bool withSymbol = true}) {
    return _service.format(
      price: price,
      currencyCode: _salonCurrencyCode,
      withSymbol: withSymbol,
    );
  }

  double roundPrice(double amount) {
    return _service.roundForCurrency(
      amount: amount,
      currencyCode: _salonCurrencyCode,
    );
  }
}