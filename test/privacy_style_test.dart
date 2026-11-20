import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/common/currency.dart';
import 'package:rekap_rapi/common/format.dart';
import 'package:rekap_rapi/common/privacy.dart';
import 'package:rekap_rapi/common/widgets.dart';
import 'package:rekap_rapi/theme/app_style.dart';
import 'package:rekap_rapi/theme/app_theme.dart';
import 'package:rekap_rapi/theme/style_picker_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() async {
    await privacyController.set(false);
    await styleController.set(AppStyle.standard);
    activeCurrency = currencyByCode('IDR');
  });

  group('Sembunyikan nominal', () {
    test('rupiah() dan label grafik disamarkan; formatMoney tetap', () async {
      expect(rupiah(1250000), 'Rp 1.250.000');
      await privacyController.set(true);
      expect(rupiah(1250000), 'Rp •••••');
      expect(rupiah(-5000), 'Rp •••••');
      expect(compact(1500000), '•••');
      // Kolom isian di formulir memakai formatMoney: tetap terlihat.
      expect(formatMoney(1250000), 'Rp 1.250.000');
      activeCurrency = currencyByCode('AED');
      expect(rupiah(10), 'AED •••••');
    });

    test('pilihan diingat di perangkat', () async {
      await privacyController.set(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('amounts_hidden'), isTrue);
      await privacyController.toggle();
      expect(privacyController.hidden, isFalse);
      expect(prefs.getBool('amounts_hidden'), isFalse);
    });
  });

  group('Gaya tampilan', () {
    testWidgets('semua gaya membangun tema terang dan gelap', (tester) async {
      for (final s in AppStyle.values) {
        for (final b in Brightness.values) {
          final t = buildTheme(b, 'Plus Jakarta Sans', Brand.seed, s);
          final tokens = t.extension<StyleTokens>()!;
          expect(tokens.style, s);
          expect(tokens.card(tint: Brand.income).borderRadius, isNotNull);
        }
      }
    });

    testWidgets('Cyberpunk selalu gelap; Glassmorphism memakai kaca buram',
        (tester) async {
      final cyber = buildTheme(
          Brightness.light, 'Plus Jakarta Sans', Brand.seed, AppStyle.cyber);
      expect(cyber.brightness, Brightness.dark);
      expect(cyber.colorScheme.primary, Neon.cyan);
      expect(AppStyle.cyber.forcesDark, isTrue);
      final glass = StyleTokens.forStyle(AppStyle.glass, Brightness.light);
      expect(glass.blur, greaterThan(0));
      expect(StyleTokens.forStyle(AppStyle.minimal, Brightness.light).shadows,
          isEmpty);
      expect(
          StyleTokens.forStyle(AppStyle.brutal, Brightness.light).border!.width,
          greaterThan(2));
    });

    test('pilihan gaya disimpan dan dibaca kembali', () async {
      await styleController.set(AppStyle.brutal);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_style'), 'brutal');
      expect(AppStyle.parse('glass'), AppStyle.glass);
      expect(AppStyle.parse('tidak-ada'), AppStyle.standard);
    });

    for (final s in AppStyle.values) {
      testWidgets('kartu tampil tanpa galat: ${s.label}', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme:
              buildTheme(Brightness.light, 'Plus Jakarta Sans', Brand.seed, s),
          home: const Scaffold(
            body: Column(children: [
              SoftCard(child: Text('isi kartu')),
              StyledBox(tint: Brand.income, child: Text('kartu angka')),
            ]),
          ),
        ));
        expect(find.text('isi kartu'), findsOneWidget);
        expect(find.text('kartu angka'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('halaman pemilih: menekan gaya langsung memakainya',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: StylePickerPage()));
      await tester.pumpAndSettle();
      for (final s in AppStyle.values) {
        expect(find.text(s.label), findsOneWidget);
      }
      expect(find.text('Dipakai'), findsOneWidget);
      await tester.tap(find.text('Neo-Brutalism'));
      await tester.pumpAndSettle();
      expect(styleController.style, AppStyle.brutal);
      expect(tester.takeException(), isNull);
    });
  });
}
