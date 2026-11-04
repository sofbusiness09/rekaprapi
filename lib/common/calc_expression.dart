/// Hitungan sederhana untuk kolom nominal: angka bulat dengan +, − dan ×.
/// Perkalian dihitung lebih dulu daripada tambah dan kurang, seperti kalkulator biasa.
library;

const calcAdd = '+';
const calcSub = '−';
const calcMul = '×';

const calcOperators = [calcAdd, calcSub, calcMul];

/// Hasil terbesar yang diterima; di atas ini dianggap salah ketik.
final _limit = BigInt.parse('999999999999');

bool isCalcOperator(String s) => calcOperators.contains(s);

/// Menghitung [expr], mis. `12000+3×500` = 13500.
///
/// Operator di ujung diabaikan (`500+` dihitung 500). Mengembalikan null bila
/// kosong atau hasilnya terlalu besar; hasil negatif dikembalikan apa adanya.
BigInt? evalCalc(String expr) {
  final tokens = RegExp('[0-9]+|[$calcAdd$calcSub$calcMul]')
      .allMatches(expr)
      .map((m) => m.group(0)!)
      .toList();
  while (tokens.isNotEmpty && isCalcOperator(tokens.last)) {
    tokens.removeLast();
  }
  if (tokens.isEmpty || isCalcOperator(tokens.first)) return null;

  // Perkalian dulu: kelompokkan menjadi suku yang dijumlahkan atau dikurangkan.
  final terms = <BigInt>[];
  final signs = <int>[];
  var sign = 1;
  var product = BigInt.parse(tokens.first);
  for (var i = 1; i < tokens.length; i += 2) {
    final op = tokens[i];
    final next = BigInt.parse(tokens[i + 1]);
    if (op == calcMul) {
      product *= next;
      if (product > _limit) return null;
    } else {
      terms.add(product);
      signs.add(sign);
      sign = op == calcAdd ? 1 : -1;
      product = next;
    }
  }
  terms.add(product);
  signs.add(sign);

  var total = BigInt.zero;
  for (var i = 0; i < terms.length; i++) {
    total += terms[i] * BigInt.from(signs[i]);
  }
  if (total.abs() > _limit) return null;
  return total;
}

/// Menampilkan [expr] dengan pemisah ribuan dan jarak di sekitar operator.
String formatCalc(String expr) {
  final buf = StringBuffer();
  for (final m
      in RegExp('[0-9]+|[$calcAdd$calcSub$calcMul]').allMatches(expr)) {
    final t = m.group(0)!;
    if (isCalcOperator(t)) {
      buf.write(' $t ');
    } else {
      buf.write(_group(t));
    }
  }
  return buf.toString();
}

String _group(String digits) {
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write('.');
    out.write(digits[i]);
  }
  return out.toString();
}
