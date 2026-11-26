import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_gate.dart';
import 'auth/url_auth_hint.dart';
import 'common/privacy.dart';
import 'l10n/l10n.dart';
import 'config.dart';
import 'theme/app_style.dart';
import 'theme/app_theme.dart';
import 'settings/input_prefs.dart';
import 'theme/background_controller.dart';
import 'theme/font_controller.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  await fontController.load();
  await inputPrefs.load();
  await backgroundController.load();
  await privacyController.load();
  await styleController.load();
  await languageController.load();
  // Dibaca sebelum Supabase menghapus parameter tautan email dari alamat.
  UrlAuthHint.read(Uri.base);
  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
    // Tautan reset dari email sering dibuka di peramban atau perangkat lain
    // daripada yang meminta; alur PKCE gagal di sana, alur implisit tidak.
    authOptions:
        const FlutterAuthClientOptions(authFlowType: AuthFlowType.implicit),
  );
  runApp(const RekapRapiApp());
}

class RekapRapiApp extends StatelessWidget {
  const RekapRapiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        themeController,
        fontController,
        backgroundController,
        privacyController,
        styleController,
      ]),
      builder: (context, _) => MaterialApp(
        title: 'RekapRapi',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light, fontController.font.family,
            backgroundController.preset.accent, styleController.style),
        darkTheme: buildTheme(Brightness.dark, fontController.font.family,
            backgroundController.preset.accent, styleController.style),
        // Cyberpunk selalu gelap.
        themeMode: styleController.style.forcesDark
            ? ThemeMode.dark
            : themeController.mode,
        // Ukuran huruf sistem yang sangat besar membuat kartu dan bilah bawah
        // terpotong; dibatasi sedikit di atas normal.
        builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9, maxScaleFactor: 1.1, child: child!),
        home: const AuthGate(),
      ),
    );
  }
}
