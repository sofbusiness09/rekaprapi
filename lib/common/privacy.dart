import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sembunyikan nominal untuk privasi (ikon mata). Disimpan per perangkat; saat
/// aplikasi dibuka lagi keadaannya sama seperti terakhir.
class PrivacyController extends ChangeNotifier {
  static const _key = 'amounts_hidden';

  bool _hidden = false;
  bool get hidden => _hidden;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hidden = prefs.getBool(_key) ?? false;
    } catch (_) {
      // Penyimpanan tidak tersedia: nominal tampil.
    }
    notifyListeners();
  }

  Future<void> set(bool hidden) async {
    if (_hidden == hidden) return;
    _hidden = hidden;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, hidden);
    } catch (_) {
      // Tetap berlaku selama aplikasi terbuka walau gagal disimpan.
    }
  }

  Future<void> toggle() => set(!_hidden);
}

final privacyController = PrivacyController();
