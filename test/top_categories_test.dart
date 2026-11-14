import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/cash/cash_form.dart';
import 'package:rekap_rapi/cash/cash_models.dart';
import 'package:rekap_rapi/common/amount_field.dart';

List<Category> _cats(List<String> names) =>
    [for (final n in names) Category(n.toLowerCase(), n, 'out', false)];

List<String> _names(List<Category> c) => [for (final x in c) x.name];

void main() {
  group('splitTopCategories', () {
    final eight = _cats(['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']);

    test('enam kategori atau kurang ditampilkan semua', () {
      final six = _cats(['A', 'B', 'C', 'D', 'E', 'F']);
      final r = splitTopCategories(six, const {'f': 9});
      expect(_names(r.$1), ['A', 'B', 'C', 'D', 'E', 'F']);
      expect(r.$2, isEmpty);
    });

    test('lima tersering di depan, sisanya tersembunyi', () {
      final r = splitTopCategories(
          eight, const {'h': 9, 'g': 7, 'c': 5, 'a': 2, 'f': 1});
      expect(_names(r.$1), ['H', 'G', 'C', 'A', 'F']);
      expect(_names(r.$2), ['B', 'D', 'E']);
    });

    test('tanpa riwayat pemakaian: urutan nama', () {
      final r = splitTopCategories(eight, const {});
      expect(_names(r.$1), ['A', 'B', 'C', 'D', 'E']);
      expect(_names(r.$2), ['F', 'G', 'H']);
    });

    test('kategori terpilih selalu tampil walau bukan lima besar', () {
      final r = splitTopCategories(eight, const {}, selectedId: 'h');
      expect(_names(r.$1), ['A', 'B', 'C', 'D', 'E', 'H']);
      expect(_names(r.$2), ['F', 'G']);
    });
  });

  testWidgets('keyboard: C di baris atas, Selesai di kanan bawah',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AmountField(controller: TextEditingController())),
      ));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      Offset at(String label) =>
          tester.getCenter(find.widgetWithText(FilledButton, label).first);
      final c = at('C'), seven = at('7'), zero = at('0'), done = at('Selesai');

      // C di atas semua angka dan di kolom paling kiri; Selesai di kolom paling kanan.
      expect(c.dy, lessThan(seven.dy));
      expect(c.dx, closeTo(seven.dx, 1));
      expect(done.dx, greaterThan(at('000').dx));
      // Selesai setinggi dua baris: pusatnya di antara baris 1-2-3 dan baris 0.
      expect(done.dy, greaterThan(at('1').dy));
      expect(done.dy, lessThan(zero.dy));
      // C tidak lagi bersebelahan dengan Selesai.
      expect((c.dy - done.dy).abs(), greaterThan(150));
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets('cari kategori: mengetik menyempitkan daftar, tekan memilih',
      (tester) async {
    String? picked;
    final cats = _cats(['Sewa', 'Servis motor', 'Pajak', 'Asuransi']);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await showCategorySearch(context,
                categories: cats, income: false),
            child: const Text('buka'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();

    // Tanpa kata cari: semua tampil.
    for (final n in ['Sewa', 'Servis motor', 'Pajak', 'Asuransi']) {
      expect(find.text(n), findsOneWidget);
    }

    await tester.enterText(find.byType(TextField), 'se');
    await tester.pump();
    expect(find.text('Pajak'), findsNothing);
    expect(find.text('Asuransi'), findsNothing);
    expect(find.text('Sewa'), findsOneWidget);
    expect(find.text('Servis motor'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('Tidak ada kategori yang cocok.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'MOTOR');
    await tester.pump();
    await tester.tap(find.text('Servis motor'));
    await tester.pumpAndSettle();
    expect(picked, 'servis motor');
  });
}
