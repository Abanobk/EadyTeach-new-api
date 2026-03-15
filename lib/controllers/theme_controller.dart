import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages light/dark theme with persistence.
class ThemeController extends ChangeNotifier {
  static const _prefKey = 'theme_is_dark';

  bool _isDark = true;

  bool get isDark => _isDark;

  ThemeController() {
    _loadFromPrefs();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _isDark = prefs.getBool(_prefKey) ?? true;
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, _isDark);
  }

  void toggleTheme() {
    _isDark = !_isDark;
    notifyListeners();
    _saveToPrefs();
  }
}
