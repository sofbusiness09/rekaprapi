import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/scan/receipt_parser.dart';

List<ReceiptLine> _lines(String text) => [
      for (final l in text.split('\n'))
        if (l.trim().isNotEmpty) ReceiptLine(l.trim()),
    ];

final _now = DateTime(2026, 11, 17, 12);

void main() {
  group('amountsIn', () {
    test('berbagai cara menulis rupiah', () {
      expect(amountsIn('45.000'), [45000]);
      expect(amountsIn('Rp 1.250.000,00'), [1250000]);
      expect(amountsIn('45,000'), [45000]);
      expect(amountsIn('Rp45.000,-'), [45000]);
      expect(amountsIn('TOTAL 128500'), [128500]);
      expect(amountsIn('2 x 12.500   25.000'), [12500, 25000]);
    });

    test('angka kecil dan kode panjang diabaikan', () {
      expect(amountsIn('Qty 2'), isEmpty);
      expect(amountsIn('NPWP 0123456789012345'), isEmpty);
    });
  });

  test('nota minimarket: total bayar, bukan tunai atau kembalian', () {
    final r = parseReceipt(_lines('''
INDOMARET MAWAR
Jl. Mawar No. 5 Tuban
17.11.2026 14:22  KSR: ANI
AQUA 600ML      2   3.500    7.000
ROTI TAWAR      1  15.000   15.000
SUBTOTAL                    22.000
DISKON                      -2.000
TOTAL BAYAR                 20.000
TUNAI                       50.000
KEMBALI                     30.000
'''), now: _now);
    expect(r.total, 20000);
    expect(r.date, DateTime(2026, 11, 17));
    expect(r.merchant, 'INDOMARET MAWAR');
  });

  test('angka total di baris berikutnya', () {
    final r = parseReceipt(_lines('''
Warung Bu Siti
Total
Rp 35.000
Tunai
Rp 50.000
'''), now: _now);
    expect(r.total, 35000);
    expect(r.merchant, 'Warung Bu Siti');
  });

  test('grand total lebih dipercaya daripada total', () {
    final r = parseReceipt(_lines('''
KOPI KENANGAN
Total          40.000
Service         4.000
PPN             4.400
Grand Total    48.400
'''), now: _now);
    expect(r.total, 48400);
  });

  test('kata TOTAL dan angkanya terpisah kolom: dipasangkan menurut posisi',
      () {
    // ML Kit sering memisah kolom kiri dan kanan menjadi baris berbeda.
    const lines = [
      ReceiptLine('APOTEK SEHAT', top: 10, bottom: 30, left: 50),
      ReceiptLine('TOTAL', top: 200, bottom: 220, left: 20),
      ReceiptLine('TUNAI', top: 230, bottom: 250, left: 20),
      ReceiptLine('67.500', top: 202, bottom: 219, left: 300),
      ReceiptLine('100.000', top: 231, bottom: 249, left: 300),
    ];
    expect(parseReceipt(lines, now: _now).total, 67500);
  });

  test('tanpa kata kunci: angka terbesar selain tunai', () {
    final r = parseReceipt(_lines('''
Toko Makmur
Beras 5kg   72.000
Minyak      18.000
Tunai      100.000
'''), now: _now);
    expect(r.total, 72000);
  });

  test('tanggal: berbagai format, dan tanggal masa depan diabaikan', () {
    expect(findDate('Tgl: 05/11/26', now: _now), DateTime(2026, 11, 5));
    expect(findDate('2026-11-03 09:10', now: _now), DateTime(2026, 11, 3));
    expect(findDate('3 Nov 2026', now: _now), DateTime(2026, 11, 3));
    expect(findDate('12 Agustus 2026', now: _now), DateTime(2026, 8, 12));
    expect(findDate('31/02/2026', now: _now), isNull);
    expect(findDate('01/12/2027', now: _now), isNull);
    expect(findDate('tanpa tanggal', now: _now), isNull);
  });

  test('nota kosong atau tidak terbaca', () {
    final r = parseReceipt(const [], now: _now);
    expect(r.isEmpty, isTrue);
  });

  test('tebakan kategori dari nama toko', () {
    const cats = [
      ('c1', 'Makan & Minum'),
      ('c2', 'Belanja'),
      ('c3', 'Transportasi'),
      ('c4', 'Kesehatan'),
      ('c5', 'Tagihan'),
    ];
    expect(guessCategory('INDOMARET MAWAR', cats), 'c2');
    expect(guessCategory('Kopi Kenangan', cats), 'c1');
    expect(guessCategory('SPBU 54.123 PERTAMINA', cats), 'c3');
    expect(guessCategory('Apotek K-24', cats), 'c4');
    expect(guessCategory('Token PLN', cats), 'c5');
    expect(
        guessCategory('Toko tak dikenal', const [('c9', 'Lainnya')]), isNull);
    expect(guessCategory('xyz', cats), isNull);
  });
}
