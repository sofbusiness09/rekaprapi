import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth/auth_gate.dart';
import 'config.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await themeController.load();
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  runApp(const RekapRapiApp());
}

class RekapRapiApp extends StatelessWidget {
  const RekapRapiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) => MaterialApp(
        title: 'RekapRapi',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: themeController.mode,
        // Ukuran huruf sistem yang sangat besar membuat kartu dan bilah bawah
        // terpotong; dibatasi sedikit di atas normal.
        builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9, maxScaleFactor: 1.1, child: child!),
        home: const AuthGate(),
      ),
    );
  }
}
