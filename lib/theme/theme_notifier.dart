import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/session_manager.dart';

class ThemeNotifier extends ChangeNotifier {
  ThemeMode _currentTheme = ThemeMode.system;

  ThemeMode get currentTheme => _currentTheme;

  ThemeNotifier() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final themeModeString = await SessionManager.getThemeMode();
    _currentTheme = themeModeString == 'light' 
        ? ThemeMode.light 
        : themeModeString == 'dark' 
            ? ThemeMode.dark 
            : ThemeMode.system;
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    _currentTheme = mode;
    
    // Save to SessionManager
    final value = mode == ThemeMode.light 
        ? 'light' 
        : mode == ThemeMode.dark 
            ? 'dark' 
            : 'system';
    await SessionManager.saveThemeMode(value);
    
    // ✅ Notify all listeners (theme change වහාම apply වෙයි)
    notifyListeners();
  }

  Future<void> refreshTheme() async {
    await _loadTheme();
  }
}