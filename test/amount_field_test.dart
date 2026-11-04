import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/common/amount_field.dart';
import 'package:rekap_rapi/settings/input_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<TextEditingController> _open(WidgetTester tester) async {
  final controller = TextEditingController();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: AmountField(
          controller: controller,
          title: 'Jumlah',
          decoration: const InputDecoration(labelText: 'Jumlah'),
        ),
      ),
    ),
  ));
  await tester.tap(find.byType(TextField));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _keys(WidgetTester tester, List<String> labels) async {
  for (final l in labels) {
    await tester.tap(find.widgetWithText(FilledButton, l).first);
    await tester.pump();
  }
}

/// Menjalankan tes seolah di [platform]; harus dikembalikan sebelum tes selesai.
void platformTest(String name, TargetPlatform platform,
    Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    // Ukuran layar ponsel agar semua tombol keyboard kalkulator terlihat.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}

void main() {
  platformTest(
      'di ponsel: tombol 000 dan Selesai mengisi kolom', TargetPlatform.android,
      (tester) async {
    final c = await _open(tester);
    expect(find.text('000'), findsOneWidget);
    expect(find.text('00'), findsOneWidget);

    await _keys(tester, ['2', '5', '000', 'Selesai']);
    await tester.pumpAndSettle();
    expect(c.text, '25.000');
  });

  platformTest('kali dan tambah dihitung saat Selesai', TargetPlatform.android,
      (tester) async {
    final c = await _open(tester);
    // 12 × 2.500 + 5.000 = 35.000
    await _keys(tester, ['1', '2', '×', '2', '5', '00', '+', '5', '000']);
    expect(find.text('= 35.000'), findsOneWidget);
    await _keys(tester, ['Selesai']);
    await tester.pumpAndSettle();
    expect(c.text, '35.000');
  });

  platformTest(
      'tombol = menampilkan total di layar kalkulator', TargetPlatform.android,
      (tester) async {
    final c = await _open(tester);
    await _keys(tester, ['3', '×', '4', '=']);
    expect(find.text('12'), findsWidgets);
    await _keys(tester, ['Selesai']);
    await tester.pumpAndSettle();
    expect(c.text, '12');
  });

  platformTest('nol di depan dan 000 di awal diabaikan', TargetPlatform.android,
      (tester) async {
    final c = await _open(tester);
    await _keys(tester, ['000', '0', '7', 'Selesai']);
    await tester.pumpAndSettle();
    expect(c.text, '7');
  });

  platformTest('hasil negatif tidak bisa disimpan', TargetPlatform.android,
      (tester) async {
    final c = await _open(tester);
    await _keys(tester, ['1', '0', '−', '3', '0']);
    expect(find.text('Hasil negatif'), findsOneWidget);
    final done = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Selesai'));
    expect(done.onPressed, isNull);
    expect(c.text, '');
  });

  platformTest('nilai yang sudah ada dibuka kembali di kalkulator',
      TargetPlatform.android, (tester) async {
    final c = TextEditingController(text: '12.500');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AmountField(controller: c)),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('12.500'), findsWidgets);
    await _keys(tester, ['+', '5', '00', 'Selesai']);
    await tester.pumpAndSettle();
    expect(c.text, '13.000');
  });

  platformTest('di komputer tetap kolom ketik biasa', TargetPlatform.windows,
      (tester) async {
    final c = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AmountField(controller: c)),
    ));
    await tester.enterText(find.byType(TextField), '1250000');
    expect(c.text, '1.250.000');
    expect(find.text('000'), findsNothing);
  });

  platformTest('dimatikan di Pengaturan: keyboard bawaan ponsel dipakai',
      TargetPlatform.android, (tester) async {
    SharedPreferences.setMockInitialValues({});
    await inputPrefs.setCalcKeypad(false);
    try {
      final c = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AmountField(controller: c)),
      ));
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.readOnly, isFalse);
      expect(field.keyboardType, TextInputType.number);

      await tester.enterText(find.byType(TextField), '2500000');
      expect(c.text, '2.500.000');
      expect(find.text('000'), findsNothing);
    } finally {
      await inputPrefs.setCalcKeypad(true);
    }
  });

  platformTest('pilihan tersimpan dan dimuat kembali', TargetPlatform.android,
      (tester) async {
    SharedPreferences.setMockInitialValues({'calc_keypad': false});
    await inputPrefs.load();
    expect(inputPrefs.calcKeypad, isFalse);

    SharedPreferences.setMockInitialValues({});
    await inputPrefs.load();
    expect(inputPrefs.calcKeypad, isTrue, reason: 'bawaan: kalkulator aktif');
  });
}
