import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/cash/cash_models.dart';
import 'package:rekap_rapi/debts/debt_models.dart';
import 'package:rekap_rapi/reports/report_visuals.dart';
import 'package:rekap_rapi/settings/home_prefs.dart';

Map<String, dynamic> _row(String name, int total, [String type = 'out']) =>
    {'category_name': name, 'type': type, 'total': total};

Debt _debt(String kind, int remaining, DateTime? due) => Debt.fromMap({
      'id': '$kind$remaining',
      'contact_id': 'c',
      'kind': kind,
      'amount': remaining,
      'cash_moved': false,
      'debt_date': '2026-11-01',
      'due_date': due == null
          ? null
          : '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}',
      'created_at': '2026-11-01T00:00:00Z',
      'paid': 0,
      'remaining': remaining,
    });

void main() {
  test('warna kategori tetap per nama, bukan hijau/abu bertingkat', () {
    expect(categoryColor('Sewa tempat'), categoryColor('Sewa tempat'));
    expect(categoryColor('Gaji karyawan'), isNot(categoryColor('Sewa tempat')));
    expect(categoryColor('Kategori buatan saya'),
        categoryColor('Kategori buatan saya'));
  });

  test('kategori yang tampil bersama tidak pernah berwarna sama', () {
    // Kombinasi dari laporan pengguna: beberapa sempat sama-sama merah muda.
    final names = [
      'BBM',
      'Bermain Anak',
      'Makan & Minum',
      'Kopi',
      'Makan',
      'Listrik dan air',
    ];
    final colors = distinctCategoryColors(names);
    expect(colors.toSet().length, names.length);
    // Kategori terbesar tetap memakai warna pilihannya.
    expect(colors.first, categoryColor('BBM'));
  });

  test('tanda naik/turun dari periode lalu', () {
    expect(changeLabel(132, 100), '▲ 32%');
    expect(changeLabel(90, 100), '▼ 10%');
    expect(changeLabel(50, 0), 'Baru');
    expect(changeLabel(50, null), isNull);
  });

  test('sisa utang dikelompokkan menurut jatuh tempo', () {
    final now = DateTime(2026, 11, 28);
    final b = DueBuckets.of([
      _debt('receivable', 100, DateTime(2026, 11, 20)),
      _debt('receivable', 200, DateTime(2026, 12, 2)),
      _debt('receivable', 300, DateTime(2027, 1, 10)),
      _debt('receivable', 400, null),
    ], now: now);
    expect([b.overdue, b.thisWeek, b.later, b.noDate], [100, 200, 300, 400]);
  });

  testWidgets('Pengeluaran di kiri; ketuk kategori menampilkannya di tengah',
      (tester) async {
    var income = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (context, setState) => CategoryBreakdown(
              rows: [
                _row('Belanja stok', 600),
                _row('Sewa tempat', 300),
                _row('Listrik dan air', 100),
                _row('Penjualan', 900, 'in'),
              ],
              previous: [_row('Belanja stok', 500)],
              income: income,
              onToggle: (v) => setState(() => income = v),
            ),
          ),
        ),
      ),
    ));
    final out = tester.getCenter(find.text('Pengeluaran'));
    final inc = tester.getCenter(find.text('Pemasukan'));
    expect(out.dx, lessThan(inc.dx));
    // Bawaan: kategori terbesar di tengah donat, dengan tanda naik.
    expect(find.text('60%'), findsWidgets);
    expect(find.text('▲ 20%'), findsOneWidget);
    expect(find.text('Baru'), findsNWidgets(2));

    await tester.tap(find.text('Sewa tempat').last);
    await tester.pump();
    expect(find.text('Sewa tempat'), findsNWidgets(2));

    await tester.tap(find.text('Pemasukan'));
    await tester.pump();
    expect(find.text('Penjualan'), findsWidgets);
    expect(find.text('Belanja stok'), findsNothing);
  });

  testWidgets('kalender periode panjang bisa pindah bulan', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SpendingCalendar(
            month: DateTime(2026, 11, 28),
            from: DateTime(2026, 1, 1),
            to: DateTime(2026, 12, 31),
            points: [DailyPoint(DateTime(2026, 10, 5), 0, 80000, 0)],
          ),
        ),
      ),
    ));
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pump();
    expect(find.text('Oktober 2026'), findsOneWidget);
    expect(find.text('31'), findsOneWidget);
    await tester.tap(find.text('5'));
    await tester.pump();
    expect(find.textContaining('80.000'), findsOneWidget);
  });

  test('pilihan grafik Rekapan tersimpan; bawaannya semua tampil', () {
    const p = HomePrefs();
    expect([p.rpFlow, p.rpProfit, p.rpCategory, p.rpCalendar, p.rpDue],
        everyElement(isTrue));
    final off = HomePrefs.fromJson(p.copyWith(rpCalendar: false).toJson());
    expect(off.rpCalendar, isFalse);
    expect(off.rpCategory, isTrue);
    // Pilihan lama tanpa kunci baru: tetap tampil semua.
    expect(HomePrefs.fromJson(const {}).rpDue, isTrue);
  });

  testWidgets('kalender pengeluaran menampilkan semua tanggal bulan itu',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SpendingCalendar(
            month: DateTime(2026, 11),
            points: [
              DailyPoint(DateTime(2026, 11, 3), 0, 50000, 0),
              DailyPoint(DateTime(2026, 11, 4), 0, 150000, 0),
            ],
          ),
        ),
      ),
    ));
    expect(find.text('30'), findsOneWidget);
    expect(find.text('31'), findsNothing);
    await tester.tap(find.text('4'));
    await tester.pump();
    expect(find.textContaining('150.000'), findsOneWidget);
  });
}
