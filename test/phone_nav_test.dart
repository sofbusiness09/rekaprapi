import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/common/floating_nav_bar.dart';
import 'package:rekap_rapi/common/widgets.dart';

const _items = [
  FloatingNavItem(Icons.bar_chart_outlined, Icons.bar_chart, 'Rekapan'),
  FloatingNavItem(Icons.receipt_long_outlined, Icons.receipt_long, 'Transaksi'),
  FloatingNavItem(Icons.handshake_outlined, Icons.handshake, 'Utang'),
  FloatingNavItem(Icons.person_outline, Icons.person, 'Profil'),
];

void main() {
  testWidgets('panel bawah: + di tengah, Profil paling kanan', (tester) async {
    var center = 0;
    final selected = <int>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: FloatingNavBar(
          items: _items,
          selectedIndex: 0,
          onSelected: selected.add,
          onCenter: () => center++,
        ),
      ),
    ));

    final plus = tester.getCenter(find.byIcon(Icons.add_rounded));
    final trans = tester.getCenter(find.byIcon(Icons.receipt_long_outlined));
    final utang = tester.getCenter(find.byIcon(Icons.handshake_outlined));
    final profil = tester.getCenter(find.byIcon(Icons.person_outline));
    // Urutan: Rekapan, Transaksi, +, Utang, Profil.
    expect(trans.dx, lessThan(plus.dx));
    expect(plus.dx, lessThan(utang.dx));
    expect(utang.dx, lessThan(profil.dx));

    await tester.tap(find.byIcon(Icons.add_rounded));
    expect(center, 1);
    await tester.tap(find.byIcon(Icons.person_outline));
    expect(selected, [3]);
  });

  testWidgets('layar HP sempit: semua nama tab tampil tanpa meluap',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2.0; // lebar 360
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: FloatingNavBar(
            items: _items,
            selectedIndex: 1,
            onSelected: (_) {},
            onCenter: () {}),
      ),
    ));
    for (final n in ['Rekapan', 'Transaksi', 'Utang', 'Profil']) {
      expect(find.text(n), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('tanpa onCenter tidak ada tombol +', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar:
            FloatingNavBar(items: _items, selectedIndex: 0, onSelected: (_) {}),
      ),
    ));
    expect(find.byIcon(Icons.add_rounded), findsNothing);
  });

  Future<void> row(WidgetTester tester, {String? status, String? note}) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            child: EntryRow(
              icon: Icons.storefront_rounded,
              iconColor: Colors.green,
              title: 'Penjualan',
              amount: '+50.000',
              amountColor: Colors.green,
              sub: '14:20',
              status: status,
              note: note,
            ),
          ),
        ),
      ));

  testWidgets('catatan tampil di bawah nominal, rata kanan', (tester) async {
    await row(tester, note: 'Kopi susu 2 gelas');
    final note = tester.getRect(find.text('Kopi susu 2 gelas'));
    final amount = tester.getRect(find.text('+50.000'));
    expect(note.top, greaterThan(amount.bottom - 1));
    expect(note.right, closeTo(amount.right, 1));

    // Dengan status (catatan utang), catatan turun ke baris berikutnya.
    await row(tester, status: 'Belum lunas', note: 'bayar Jumat');
    final status = tester.getRect(find.text('Belum lunas'));
    final n2 = tester.getRect(find.text('bayar Jumat'));
    expect(n2.top, greaterThan(status.bottom - 1));

    // Tanpa catatan: tidak ada baris tambahan.
    await row(tester);
    expect(find.text('Kopi susu 2 gelas'), findsNothing);
  });
}
