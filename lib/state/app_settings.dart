import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences that affect the whole app: theme mode and font scale.
class AppSettings extends ChangeNotifier {
  static const String _themeKey = 'app_theme_mode';
  static const String _fontKey = 'app_font_scale';

  /// Font scale presets shown in settings.
  static const List<double> fontOptions = [0.9, 1.0, 1.12, 1.25];

  ThemeMode themeMode = ThemeMode.dark;
  double fontScale = 1.0;

  String get fontLabel => labelOf(fontScale);

  static String labelOf(double value) {
    if (value <= 0.92) return '小';
    if (value <= 1.02) return '标准';
    if (value <= 1.16) return '大';
    return '特大';
  }

  static String themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.dark => '深色',
        ThemeMode.light => '浅色',
        ThemeMode.system => '跟随系统',
      };

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedTheme = prefs.getString(_themeKey);
    themeMode = ThemeMode.values.firstWhere(
      (m) => m.name == savedTheme,
      orElse: () => ThemeMode.dark,
    );
    // The value may have been written as an int by an external tool, so read
    // it dynamically instead of getDouble (which throws on int).
    final savedFont = prefs.get(_fontKey);
    if (savedFont is num && savedFont > 0) {
      fontScale = savedFont.toDouble().clamp(0.8, 1.4);
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (themeMode == mode) return;
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  Future<void> setFontScale(double value) async {
    final next = value.clamp(0.8, 1.4);
    if (fontScale == next) return;
    fontScale = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontKey, next);
  }
}
