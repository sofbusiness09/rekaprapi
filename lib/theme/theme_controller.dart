import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pilihan tampilan: Terang, Gelap, atau mengikuti perangkat. Disimpan di perangkat ini.
class ThemeController extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = switch (prefs.getString(_key)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // Penyimpanan tidak tersedia: tetap mengikuti perangkat.
    }
    notifyListeners();
  }

  Future<void> set(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key,
          switch (mode) {
            ThemeMode.light => 'light',
            ThemeMode.dark => 'dark',
            ThemeMode.system => 'system',
          });
    } catch (_) {
      // Pilihan tetap berlaku selama aplikasi terbuka walau gagal disimpan.
    }
  }
}

/// Satu pengatur tema untuk seluruh aplikasi.
final themeController = ThemeController();
