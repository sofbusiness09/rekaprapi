import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu pilihan warna latar gradasi, dengan nada terang dan gelap.
class BackgroundPreset {
  const BackgroundPreset(
      this.id, this.name, this.light, this.dark, this.accent);

  final String id;
  final String name;

  /// Warna di bagian atas layar pada tema terang dan gelap; memudar ke warna latar.
  final Color light;
  final Color dark;

  /// Warna aksen tombol dan menu yang serasi dengan gradasi ini.
  final Color accent;

  Color tint(Brightness b) => b == Brightness.dark ? dark : light;
}

const backgroundPresets = <BackgroundPreset>[
  BackgroundPreset('hijau', 'Hijau', Color(0xFFBDE8D3), Color(0xFF0E4A34),
      Color(0xFF0E9F6E)),
  BackgroundPreset(
      'biru', 'Biru', Color(0xFFC4DBF7), Color(0xFF12315C), Color(0xFF2F7DE1)),
  BackgroundPreset(
      'ungu', 'Ungu', Color(0xFFD8CCF4), Color(0xFF2B1A5C), Color(0xFF7C4DDB)),
  BackgroundPreset('oranye', 'Oranye', Color(0xFFF8D8B4), Color(0xFF5A3410),
      Color(0xFFE8821A)),
  BackgroundPreset('merah', 'Merah muda', Color(0xFFF5CBDF), Color(0xFF5C1A3A),
      Color(0xFFD6407F)),
];

BackgroundPreset presetById(String? id) => backgroundPresets
    .firstWhere((p) => p.id == id, orElse: () => backgroundPresets.first);

/// Latar gradasi layar utama: hidup atau mati, dan warnanya. Disimpan di perangkat ini.
class BackgroundController extends ChangeNotifier {
  static const _enabledKey = 'bg_gradient';
  static const _presetKey = 'bg_preset';

  bool _enabled = true;
  BackgroundPreset _preset = backgroundPresets.first;

  bool get enabled => _enabled;
  BackgroundPreset get preset => _preset;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? true;
      _preset = presetById(prefs.getString(_presetKey));
    } catch (_) {
      // Penyimpanan tidak tersedia: memakai pilihan bawaan.
    }
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_enabled == value) return;
    _enabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (_) {
      // Pilihan tetap berlaku selama aplikasi terbuka walau gagal disimpan.
    }
  }

  Future<void> setPreset(BackgroundPreset preset) async {
    if (_preset.id == preset.id) return;
    _preset = preset;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_presetKey, preset.id);
    } catch (_) {
      // Pilihan tetap berlaku selama aplikasi terbuka walau gagal disimpan.
    }
  }
}

/// Satu pengatur latar untuk seluruh aplikasi.
final backgroundController = BackgroundController();

/// Gradasi latar untuk kecerahan tema saat ini, atau null bila dimatikan.
/// Memudar dari warna pilihan di atas ke warna latar polos di bagian bawah, jadi
/// kartu putih dan tulisan di bagian bawah layar tetap berada di atas warna polos.
Gradient? backgroundGradient(Brightness brightness, Color base) {
  if (!backgroundController.enabled) return null;
  return LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundController.preset.tint(brightness), base],
    stops: const [0, 0.65],
  );
}
