import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/common/calc_expression.dart';

int? v(String expr) => evalCalc(expr)?.toInt();

void main() {
  group('evalCalc', () {
    test('angka tunggal dan tambah', () {
      expect(v('12000'), 12000);
      expect(v('12000+3000'), 15000);
      expect(v('1+2+3'), 6);
    });

    test('kali lebih dulu daripada tambah dan kurang', () {
      expect(v('2+3×4'), 14);
      expect(v('3×4+2'), 14);
      expect(v('10−2×3'), 4);
      expect(v('2×3×4'), 24);
      expect(v('5×2+3×4'), 22);
    });

    test('contoh nyata: 12 barang x Rp 2.500 ditambah ongkos', () {
      expect(v('12×2500+5000'), 35000);
      expect(v('3×1000+2×500'), 4000);
    });

    test('kurang dan hasil negatif', () {
      expect(v('100−30'), 70);
      expect(v('30−100'), -70);
      expect(v('10−3−2'), 5);
    });

    test('operator di ujung diabaikan, kosong dan salah bentuk menjadi null',
        () {
      expect(v('500+'), 500);
      expect(v('500×'), 500);
      expect(evalCalc(''), isNull);
      expect(evalCalc('+5'), isNull);
      expect(evalCalc('×'), isNull);
    });

    test('hasil terlalu besar ditolak', () {
      expect(evalCalc('999999999×999999999'), isNull);
      expect(v('999999999999'), 999999999999);
    });
  });

  group('formatCalc', () {
    test('pemisah ribuan dan jarak operator', () {
      expect(formatCalc('12000+3×500'), '12.000 + 3 × 500');
      expect(formatCalc('1234567'), '1.234.567');
      expect(formatCalc(''), '');
      expect(formatCalc('500−'), '500 − ');
    });
  });
}
