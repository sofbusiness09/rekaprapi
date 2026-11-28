import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/common/amount_field.dart';

Future<(TextEditingController, List<int>)> _page(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final amount = TextEditingController();
  final saves = <int>[];
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      appBar: AppBar(title: const Text('Catat pengeluaran')),
      body: StatefulBuilder(
        builder: (context, setState) => CalcHost(
          bottomBar: FilledButton(
            onPressed: () => saves.add(int.parse(
                amount.text.isEmpty ? '0' : amount.text.replaceAll('.', ''))),
            child: const Text('Simpan'),
          ),
          child: ListView(children: [
            AmountField(controller: amount, autofocus: true),
            for (var i = 0; i < 6; i++)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Kolom $i'),
              ),
            const TextField(decoration: InputDecoration(labelText: 'Catatan')),
          ]),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (amount, saves);
}

Future<void> _keys(WidgetTester tester, List<String> labels) async {
  for (final l in labels) {
    await tester.tap(find.widgetWithText(FilledButton, l).first);
    await tester.pump();
  }
}

/// Keyboard kalkulator hanya dipakai di ponsel.
final _android = TargetPlatformVariant.only(TargetPlatform.android);

void main() {
  testWidgets('kalkulator menempel di bawah; Simpan tetap terlihat di atasnya',
      (tester) async {
    final (amount, saves) = await _page(tester);
    // Kolom jumlah otomatis aktif: kalkulator tampil tanpa menutup halaman.
    expect(find.text('000'), findsOneWidget);
    final save = tester.getRect(find.text('Simpan'));
    final seven = tester.getRect(find.widgetWithText(FilledButton, '7'));
    expect(save.bottom, lessThan(seven.top));

    // Kolom ikut berubah selama mengetik, termasuk hasil hitungan.
    await _keys(tester, ['1', '2', '×', '2', '5', '00']);
    expect(amount.text, '30.000');

    // Simpan bisa ditekan tanpa menutup kalkulator dulu.
    await tester.tap(find.text('Simpan'));
    expect(saves, [30000]);
  }, variant: _android);

  testWidgets('Selesai menurunkan kalkulator; kolom jumlah membukanya lagi',
      (tester) async {
    final (amount, _) = await _page(tester);
    await _keys(tester, ['5', '000', 'Selesai']);
    await tester.pumpAndSettle();
    expect(amount.text, '5.000');
    expect(find.text('000'), findsNothing);

    await tester.tap(find.byType(AmountField));
    await tester.pumpAndSettle();
    expect(find.text('000'), findsOneWidget);
    // Melanjutkan dari nilai yang sudah ada.
    await _keys(tester, ['0']);
    expect(amount.text, '50.000');
  }, variant: _android);

  testWidgets('hapus angka terakhir dan C mengosongkan kolom', (tester) async {
    final (amount, _) = await _page(tester);
    await _keys(tester, ['7', '5']);
    expect(amount.text, '75');
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(amount.text, '7');
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(amount.text, '');

    await _keys(tester, ['4', '000']);
    expect(amount.text, '4.000');
    await tester.tap(find.widgetWithText(FilledButton, 'C'));
    await tester.pump();
    expect(amount.text, '');
  }, variant: _android);

  testWidgets('kalkulator 4 baris; menggeser isian menurunkannya',
      (tester) async {
    await _page(tester);
    final seven = tester.getRect(find.widgetWithText(FilledButton, '7'));
    final zero = tester.getRect(find.widgetWithText(FilledButton, '0'));
    final c = tester.getRect(find.widgetWithText(FilledButton, 'C'));
    // 7 di baris atas, 0 di baris bawah: tiga jarak baris saja.
    expect(zero.top - seven.top, lessThan(3 * 56));
    // Jauh lebih pendek dari kalkulator lama (340).
    expect(tester.getSize(find.byType(CalcKeypad)).height, lessThan(280));
    expect(c.top, seven.top);
    expect(find.text('Selesai'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.text('000'), findsNothing);
    expect(find.text('Simpan'), findsOneWidget);
  }, variant: _android);

  testWidgets('kolom teks aktif: kalkulator turun agar keyboard ponsel tampil',
      (tester) async {
    await _page(tester);
    expect(find.text('000'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextField, 'Catatan'));
    await tester.pumpAndSettle();
    expect(find.text('000'), findsNothing);
    expect(find.text('Simpan'), findsOneWidget);
  }, variant: _android);
}
