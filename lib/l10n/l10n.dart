import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'en.dart';

/// Bahasa antarmuka. Teks sumber ditulis dalam Bahasa Indonesia dan dipakai sebagai
/// kunci terjemahan; bila terjemahan belum ada, teks Indonesia yang tampil.
enum AppLanguage {
  id('Bahasa Indonesia'),
  en('English (US)');

  const AppLanguage(this.label);

  final String label;

  static AppLanguage parse(String? v) =>
      AppLanguage.values.firstWhere((l) => l.name == v, orElse: () => id);
}

class LanguageController extends ChangeNotifier {
  static const _key = 'app_language';

  AppLanguage _language = AppLanguage.id;
  AppLanguage get language => _language;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _language = AppLanguage.parse(prefs.getString(_key));
    } catch (_) {
      // Penyimpanan tidak tersedia: Bahasa Indonesia.
    }
    notifyListeners();
  }

  Future<void> set(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    notifyListeners();
    // Semua teks dibangun ulang dalam bahasa baru tanpa menutup halaman.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final root = WidgetsBinding.instance.rootElement;
      if (root != null) rebuildAll(root);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, language.name);
    } catch (_) {
      // Tetap berlaku selama aplikasi terbuka walau gagal disimpan.
    }
  }
}

final languageController = LanguageController();

/// Menerjemahkan [source] (teks Indonesia) ke bahasa aktif. Tempat `{0}`, `{1}`, ...
/// diisi dari [args], baik pada teks sumber maupun terjemahannya.
String tr(String source, [List<Object?> args = const []]) {
  final text = languageController.language == AppLanguage.en
      ? (enStrings[source] ?? source)
      : source;
  if (args.isEmpty) return text;
  var out = text;
  for (var i = 0; i < args.length; i++) {
    out = out.replaceAll('{$i}', '${args[i]}');
  }
  return out;
}

/// Membangun ulang seluruh tampilan setelah bahasa berganti, tanpa menutup halaman.
void rebuildAll(BuildContext context) {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }

  (context as Element).visitChildren(visit);
}
