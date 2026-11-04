import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu pilihan jenis huruf aplikasi.
class AppFont {
  const AppFont(this.id, this.name, this.note, this.family);

  /// Disimpan di perangkat.
  final String id;
  final String name;
  final String note;

  /// Nama keluarga di Google Fonts.
  final String family;
}

const appFonts = <AppFont>[
  AppFont('jakarta', 'Plus Jakarta Sans', 'Modern dan tegas (bawaan)',
      'Plus Jakarta Sans'),
  AppFont('inter', 'Inter', 'Netral dan sangat mudah dibaca', 'Inter'),
  AppFont('nunito', 'Nunito', 'Bulat dan ramah', 'Nunito'),
  AppFont('poppins', 'Poppins', 'Geometris dan lebar', 'Poppins'),
  AppFont('merriweather', 'Merriweather', 'Klasik, berkaki seperti buku',
      'Merriweather'),
];

AppFont fontById(String? id) =>
    appFonts.firstWhere((f) => f.id == id, orElse: () => appFonts.first);

/// Pilihan jenis huruf. Disimpan di perangkat ini, seperti pilihan Terang/Gelap.
class FontController extends ChangeNotifier {
  static const _key = 'app_font';

  AppFont _font = appFonts.first;
  AppFont get font => _font;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _font = fontById(prefs.getString(_key));
    } catch (_) {
      // Penyimpanan tidak tersedia: memakai huruf bawaan.
    }
    notifyListeners();
  }

  Future<void> set(AppFont font) async {
    if (_font.id == font.id) return;
    _font = font;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, font.id);
    } catch (_) {
      // Pilihan tetap berlaku selama aplikasi terbuka walau gagal disimpan.
    }
  }
}

/// Satu pengatur jenis huruf untuk seluruh aplikasi.
final fontController = FontController();
