import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/common/format.dart';
import 'package:rekap_rapi/l10n/en.dart';
import 'package:rekap_rapi/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => languageController.set(AppLanguage.id));

  test('bawaan Bahasa Indonesia; teks tanpa terjemahan tetap tampil', () async {
    expect(tr('Simpan'), 'Simpan');
    await languageController.set(AppLanguage.en);
    expect(tr('Simpan'), 'Save');
    expect(
        tr('Teks yang belum diterjemahkan'), 'Teks yang belum diterjemahkan');
  });

  test('isian {0} terisi di kedua bahasa', () async {
    expect(tr('Kode dikirim ke {0}.', ['a@b.c']), 'Kode dikirim ke a@b.c.');
    await languageController.set(AppLanguage.en);
    expect(tr('Kode dikirim ke {0}.', ['a@b.c']), 'Code sent to a@b.c.');
    expect(tr('Backup selesai {0}: {1} baris.{2}', ['10:00', 5, '']),
        'Backup done at 10:00: 5 rows.');
  });

  test('setiap terjemahan memakai isian yang sama dengan teks aslinya', () {
    final slot = RegExp(r'\{\d+\}');
    for (final e in enStrings.entries) {
      final a = slot.allMatches(e.key).map((m) => m.group(0)).toSet();
      final b = slot.allMatches(e.value).map((m) => m.group(0)).toSet();
      expect(b, a, reason: e.key);
      expect(e.value.trim(), isNotEmpty, reason: e.key);
    }
  });

  test('tanggal dan angka ringkas mengikuti bahasa', () async {
    final d = DateTime(2026, 11, 3);
    expect(dateId(d), '3 November 2026');
    expect(compact(1500000), '1,5jt');
    await languageController.set(AppLanguage.en);
    expect(dateId(d), 'November 3, 2026');
    expect(compact(1500000), '1.5M');
    expect(compact(250000), '250K');
    expect(monthId(d), 'November 2026');
  });

  test('pilihan bahasa disimpan', () async {
    await languageController.set(AppLanguage.en);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_language'), 'en');
    expect(AppLanguage.parse('xx'), AppLanguage.id);
  });

  testWidgets('ganti bahasa memperbarui teks tanpa menutup halaman',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (_) => Text(tr('Pengaturan')))),
    ));
    expect(find.text('Pengaturan'), findsOneWidget);
    await languageController.set(AppLanguage.en);
    await tester.pump();
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
  });
}
