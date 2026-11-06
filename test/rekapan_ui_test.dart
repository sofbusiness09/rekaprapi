import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/business/business.dart';
import 'package:rekap_rapi/cash/cash_models.dart';
import 'package:rekap_rapi/cash/tx_detail_page.dart';
import 'package:rekap_rapi/common/floating_nav_bar.dart';
import 'package:rekap_rapi/common/format.dart';
import 'package:rekap_rapi/theme/background_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

CashTx _sale({bool auto = false}) => CashTx(
      id: 't1',
      type: 'in',
      amount: 95000, // 100.000 - diskon 5.000
      date: DateTime(2026, 11, 6),
      createdAt: DateTime(2026, 11, 6, 17, 5),
      isSale: true,
      costAmount: 60000,
      discountAmount: 5000,
      debtId: auto ? 'd1' : null,
      note: 'Pesanan Bu Ani',
    );

Widget _app(Widget home) => MaterialApp(home: home);

/// Layar setinggi ponsel agar semua isi halaman detail terbangun dan terlihat.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('BusinessKind', () {
    test('parse dan nilai API', () {
      expect(BusinessKind.parse('personal'), BusinessKind.personal);
      expect(BusinessKind.parse('business'), BusinessKind.business);
      expect(BusinessKind.parse(null), BusinessKind.business,
          reason: 'rekapan lama tanpa jenis = usaha');
      expect(BusinessKind.personal.apiValue, 'personal');
      expect(BusinessKind.personal.label, 'Pribadi');
    });

    test('rekapan pribadi tanpa penjualan; copyWith menjaga jenis', () {
      const b = Business(
          id: '1', name: 'Saya', role: 'owner', kind: BusinessKind.personal);
      expect(b.isPersonal, isTrue);
      expect(b.copyWith(name: 'Baru').isPersonal, isTrue);
      expect(const Business(id: '2', name: 'U', role: 'owner').isPersonal,
          isFalse);
    });
  });

  group('Detail transaksi', () {
    testWidgets('penjualan: total, modal, keuntungan, tanggal dan jam',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(TxDetailPage(
        tx: _sale(),
        category: 'Penjualan',
        recorder: 'Rina',
        canEdit: true,
      )));

      expect(find.text('Total penjualan'), findsOneWidget);
      expect(find.text(rupiah(100000)), findsOneWidget);
      expect(find.text('Modal'), findsOneWidget);
      expect(find.text(rupiah(60000)), findsOneWidget);
      expect(find.text('Keuntungan'), findsOneWidget);
      expect(find.text(rupiah(35000)), findsOneWidget,
          reason: '95.000 - 60.000');
      expect(find.textContaining('Lunas'), findsOneWidget);
      expect(find.text('6 November 2026, 17:05'), findsOneWidget);
      expect(find.text('Rina'), findsOneWidget);
      expect(find.text('Pesanan Bu Ani'), findsOneWidget);
      expect(find.text('Ubah'), findsOneWidget);
      expect(find.text('Hapus'), findsOneWidget);
    });

    testWidgets('bukan penjualan: hanya jumlah, tanpa modal dan keuntungan',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(TxDetailPage(
        tx: CashTx(
            id: 't2',
            type: 'out',
            amount: 20000,
            date: DateTime(2026, 11, 6),
            createdAt: DateTime(2026, 11, 6, 8, 30)),
        category: 'Transportasi',
        recorder: null,
        canEdit: false,
      )));

      expect(find.text('Jumlah'), findsOneWidget);
      expect(find.text('Modal'), findsNothing);
      expect(find.text('Keuntungan'), findsNothing);
      expect(find.text('Ubah'), findsNothing, reason: 'tidak boleh mengubah');
      expect(find.text('6 November 2026, 08:30'), findsOneWidget);
    });

    testWidgets('Ubah dan Hapus menutup halaman dengan aksinya',
        (tester) async {
      _phone(tester);
      String? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                      builder: (_) => TxDetailPage(
                          tx: _sale(),
                          category: 'Penjualan',
                          recorder: null,
                          canEdit: true)));
            },
            child: const Text('buka'),
          ),
        ),
      ));
      await tester.tap(find.text('buka'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hapus'));
      await tester.pumpAndSettle();
      expect(result, 'delete');
    });

    testWidgets('kas otomatis dari utang piutang diberi keterangan',
        (tester) async {
      _phone(tester);
      await tester.pumpWidget(_app(TxDetailPage(
        tx: _sale(auto: true),
        category: 'Pelunasan Piutang',
        recorder: null,
        canEdit: false,
      )));
      expect(find.text('Dibuat otomatis dari utang piutang.'), findsOneWidget);
    });
  });

  group('Waktu', () {
    test('clockId dan dateTimeId', () {
      expect(clockId(DateTime(2026, 11, 6, 5, 3)), '05:03');
      expect(dateTimeId(DateTime(2026, 11, 6), DateTime(2026, 11, 6, 17, 5)),
          '6 November 2026, 17:05');
      expect(dateTimeId(DateTime(2026, 11, 6)), '6 November 2026');
    });
  });

  group('Panel bawah melayang', () {
    testWidgets('tab terpilih menampilkan nama, lainnya hanya ikon',
        (tester) async {
      var selected = 0;
      await tester.pumpWidget(MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            bottomNavigationBar: FloatingNavBar(
              items: const [
                FloatingNavItem(Icons.home_outlined, Icons.home, 'Beranda'),
                FloatingNavItem(Icons.receipt_long_outlined, Icons.receipt_long,
                    'Transaksi'),
                FloatingNavItem(
                    Icons.handshake_outlined, Icons.handshake, 'Utang'),
                FloatingNavItem(
                    Icons.bar_chart_outlined, Icons.bar_chart, 'Rekapan'),
              ],
              selectedIndex: selected,
              onSelected: (i) => setState(() => selected = i),
            ),
          ),
        ),
      ));

      expect(find.text('Beranda'), findsOneWidget);
      expect(find.text('Transaksi'), findsNothing);

      await tester.tap(find.byIcon(Icons.handshake_outlined));
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(find.text('Utang'), findsOneWidget);
      expect(find.text('Beranda'), findsNothing);
    });
  });

  group('Latar gradasi', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('bawaan hidup; bisa dimatikan dan diganti warna', () async {
      await backgroundController.load();
      expect(backgroundController.enabled, isTrue);
      expect(backgroundGradient(Brightness.light, Colors.white), isNotNull);

      await backgroundController.setEnabled(false);
      expect(backgroundGradient(Brightness.light, Colors.white), isNull);

      await backgroundController.setEnabled(true);
      await backgroundController.setPreset(presetById('biru'));
      final g =
          backgroundGradient(Brightness.dark, Colors.black) as LinearGradient;
      expect(g.colors.first, presetById('biru').dark);
      expect(g.colors.last, Colors.black);

      await backgroundController.setPreset(backgroundPresets.first);
    });

    test('id tidak dikenal memakai warna pertama', () {
      expect(presetById('tidak-ada').id, backgroundPresets.first.id);
      expect(backgroundPresets.length, greaterThanOrEqualTo(3));
    });
  });
}
