import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pilihan cara mengetik: keyboard kalkulator bawaan aplikasi atau keyboard bawaan
/// ponsel. Disimpan di perangkat ini, seperti pilihan Terang/Gelap dan jenis huruf.
class InputPrefs extends ChangeNotifier {
  static const _key = 'calc_keypad';

  bool _calcKeypad = true;

  /// true = kolom nominal memakai keyboard kalkulator aplikasi (bawaan).
  bool get calcKeypad => _calcKeypad;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _calcKeypad = prefs.getBool(_key) ?? true;
    } catch (_) {
      // Penyimpanan tidak tersedia: memakai keyboard kalkulator.
    }
    notifyListeners();
  }

  Future<void> setCalcKeypad(bool value) async {
    if (_calcKeypad == value) return;
    _calcKeypad = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {
      // Pilihan tetap berlaku selama aplikasi terbuka walau gagal disimpan.
    }
  }
}

/// Satu pengatur cara mengetik untuk seluruh aplikasi.
final inputPrefs = InputPrefs();
