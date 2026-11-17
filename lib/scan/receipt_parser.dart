/// Membaca hasil teks nota/struk belanja (dari OCR) menjadi isian transaksi.
///
/// Murni Dart tanpa kamera atau ML Kit, supaya bisa diuji dengan contoh teks.
library;

/// Satu baris teks hasil OCR beserta posisinya (piksel gambar). Posisi dipakai
/// untuk memasangkan kata "TOTAL" dengan angka di kolom kanan pada baris yang sama.
class ReceiptLine {
  const ReceiptLine(this.text, {this.top, this.bottom, this.left});

  final String text;
  final double? top;
  final double? bottom;
  final double? left;

  double? get center =>
      top == null || bottom == null ? null : (top! + bottom!) / 2;
  double? get height => top == null || bottom == null ? null : bottom! - top!;
}

/// Hasil pembacaan nota. Semua isian boleh kosong bila tidak terbaca.
class ReceiptResult {
  const ReceiptResult({this.total, this.date, this.merchant});

  /// Jumlah yang dibayar, dalam rupiah bulat.
  final int? total;
  final DateTime? date;

  /// Nama toko (baris pertama nota), untuk catatan dan tebakan kategori.
  final String? merchant;

  bool get isEmpty => total == null && date == null && merchant == null;
}

// Urutan menentukan prioritas: yang lebih awal lebih dipercaya sebagai total akhir.
const _totalKeys = [
  'grand total',
  'total bayar',
  'total pembayaran',
  'total belanja',
  'total tagihan',
  'jumlah bayar',
  'jumlah tagihan',
  'total harga',
  'netto',
  'total',
  'jumlah',
  'tagihan',
];

// Baris yang memuat angka tetapi bukan total yang dibayar.
const _notTotal = [
  'subtotal',
  'sub total',
  'sub-total',
  'tunai',
  'cash',
  'kembali',
  'kembalian',
  'change',
  'diskon',
  'discount',
  'hemat',
  'ppn',
  'pajak',
  'tax',
  'service',
  'item',
  'qty',
  'poin',
  'point',
  'debit',
  'kredit',
  'kartu',
];

const _months = {
  'jan': 1,
  'feb': 2,
  'peb': 2,
  'mar': 3,
  'apr': 4,
  'mei': 5,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'agu': 8,
  'agt': 8,
  'aug': 8,
  'sep': 9,
  'okt': 10,
  'oct': 10,
  'nov': 11,
  'des': 12,
  'dec': 12,
};

/// Angka rupiah di dalam teks: "45.000", "45,000", "Rp 1.250.000,00", "45.000,-",
/// "45000". Angka kecil (di bawah 100) dan kode panjang tanpa pemisah diabaikan.
List<int> amountsIn(String text) {
  final out = <int>[];
  final re = RegExp(
      r'(?<![\d.,])(\d{1,3}(?:[.,]\d{3})+|\d{3,9})(?:[.,](\d{2}|-{1,2}))?(?![\d])');
  for (final m in re.allMatches(text)) {
    final digits = m.group(1)!.replaceAll(RegExp(r'[.,]'), '');
    final v = int.tryParse(digits);
    if (v == null || v < 100 || v > 1000000000) continue;
    out.add(v);
  }
  return out;
}

bool _hasKey(String lower, List<String> keys) => keys.any(lower.contains);

/// Kata kunci total dengan prioritas (0 = paling dipercaya), atau null.
int? _totalRank(String lower) {
  if (_hasKey(lower, _notTotal)) return null;
  for (var i = 0; i < _totalKeys.length; i++) {
    if (RegExp('(^|[^a-z])${RegExp.escape(_totalKeys[i])}([^a-z]|\$)')
        .hasMatch(lower)) {
      return i;
    }
  }
  return null;
}

/// Angka pada baris yang sama dengan [line] menurut posisi (kolom kanan nota).
List<int> _sameRow(ReceiptLine line, List<ReceiptLine> all) {
  final c = line.center, h = line.height;
  if (c == null || h == null) return const [];
  final out = <int>[];
  for (final o in all) {
    if (identical(o, line)) continue;
    final oc = o.center;
    if (oc == null || (oc - c).abs() > h * 0.6) continue;
    if (line.left != null && o.left != null && o.left! < line.left!) continue;
    out.addAll(amountsIn(o.text));
  }
  return out;
}

int? _findTotal(List<ReceiptLine> lines) {
  int? best;
  int? bestRank;
  for (var i = 0; i < lines.length; i++) {
    final lower = lines[i].text.toLowerCase();
    final rank = _totalRank(lower);
    if (rank == null) continue;
    // Angka di baris itu sendiri, lalu di kolom sejajar, lalu di baris berikutnya.
    var nums = amountsIn(lines[i].text);
    if (nums.isEmpty) nums = _sameRow(lines[i], lines);
    if (nums.isEmpty && i + 1 < lines.length) {
      final next = lines[i + 1].text.toLowerCase();
      if (_totalRank(next) == null && !_hasKey(next, _notTotal)) {
        nums = amountsIn(lines[i + 1].text);
      }
    }
    if (nums.isEmpty) continue;
    final v = nums.last;
    // Kata kunci yang lebih kuat menang; bila sama kuat, yang paling bawah (total akhir).
    if (bestRank == null || rank <= bestRank) {
      best = v;
      bestRank = rank;
    }
  }
  if (best != null) return best;

  // Tanpa kata kunci: angka terbesar di luar baris tunai, kembalian, dan sejenisnya.
  var max = 0;
  for (final l in lines) {
    if (_hasKey(l.text.toLowerCase(), _notTotal)) continue;
    for (final v in amountsIn(l.text)) {
      if (v > max) max = v;
    }
  }
  return max == 0 ? null : max;
}

int _year(String y) {
  final v = int.parse(y);
  return y.length == 2 ? 2000 + v : v;
}

DateTime? _valid(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 2000 || y > 2100) return null;
  final dt = DateTime(y, m, d);
  return dt.month == m ? dt : null;
}

/// Tanggal pertama yang masuk akal: 17/11/2026, 17-11-26, 17.11.2026, 2026-11-17,
/// atau 17 Nov 2026. Tanggal lebih dari sehari ke depan dari [now] diabaikan.
DateTime? findDate(String text, {DateTime? now}) {
  final limit = (now ?? DateTime.now()).add(const Duration(days: 1));
  final candidates = <DateTime>[];
  for (final m in RegExp(r'(?<!\d)(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?!\d)')
      .allMatches(text)) {
    final d = _valid(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    if (d != null) candidates.add(d);
  }
  for (final m
      in RegExp(r'(?<!\d)(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})(?!\d)')
          .allMatches(text)) {
    final d = _valid(_year(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
    if (d != null) candidates.add(d);
  }
  for (final m in RegExp(
          r'(?<!\d)(\d{1,2})[\s-]*([A-Za-z]{3})[A-Za-z]*[\s-]*(\d{4}|\d{2})(?!\d)')
      .allMatches(text)) {
    final month = _months[m[2]!.toLowerCase()];
    if (month == null) continue;
    final d = _valid(_year(m[3]!), month, int.parse(m[1]!));
    if (d != null) candidates.add(d);
  }
  for (final d in candidates) {
    if (!d.isAfter(limit)) return d;
  }
  return null;
}

/// Nama toko: baris awal yang berisi huruf dan bukan alamat, tanggal, atau angka.
String? findMerchant(List<ReceiptLine> lines) {
  const skip = [
    'jl',
    'jalan',
    'telp',
    'tel ',
    'npwp',
    'struk',
    'nota',
    'receipt',
    'kasir',
    'no.',
    'www',
    'http',
  ];
  for (final l in lines.take(5)) {
    final t = l.text.trim();
    final lower = t.toLowerCase();
    final letters = RegExp(r'[A-Za-z]').allMatches(t).length;
    if (letters < 3 || letters < t.length / 2) continue;
    if (skip.any(lower.startsWith) || _totalRank(lower) != null) continue;
    return t.length > 60 ? t.substring(0, 60) : t;
  }
  return null;
}

/// Membaca baris-baris teks nota (urut dari atas) menjadi total, tanggal, dan toko.
ReceiptResult parseReceipt(List<ReceiptLine> lines, {DateTime? now}) {
  final clean = [
    for (final l in lines)
      if (l.text.trim().isNotEmpty) l,
  ];
  return ReceiptResult(
    total: _findTotal(clean),
    date: findDate(clean.map((l) => l.text).join('\n'), now: now),
    merchant: findMerchant(clean),
  );
}

/// Kata pada nama toko atau isi nota -> kata pada nama kategori yang cocok.
const _categoryHints = <String, List<String>>{
  'belanja': [
    'indomaret',
    'alfamart',
    'alfamidi',
    'superindo',
    'hypermart',
    'giant',
    'lotte',
    'transmart',
    'carrefour',
    'supermarket',
    'minimarket',
    'swalayan',
    'toko',
    'mart',
  ],
  'makan': [
    'resto',
    'restoran',
    'rumah makan',
    'warung',
    'cafe',
    'kafe',
    'coffee',
    'kopi',
    'bakery',
    'kfc',
    'mcd',
    "mcdonald",
    'pizza',
    'bakso',
    'sate',
    'mie',
    'ayam',
  ],
  'transport': [
    'spbu',
    'pertamina',
    'shell',
    'vivo',
    'bp ',
    'parkir',
    'tol',
    'gojek',
    'grab',
    'bensin',
  ],
  'kesehatan': [
    'apotek',
    'apotik',
    'farma',
    'klinik',
    'rumah sakit',
    'rs ',
    'dokter',
    'lab',
  ],
  'tagihan': [
    'pln',
    'pdam',
    'telkom',
    'indihome',
    'listrik',
    'pulsa',
    'token',
    'bpjs',
    'internet',
  ],
};

/// Menebak kategori dari teks nota. [categories] berisi (id, nama); mengembalikan
/// id kategori pertama yang namanya cocok, atau null.
String? guessCategory(String text, List<(String, String)> categories) {
  final lower = ' ${text.toLowerCase()} ';
  for (final entry in _categoryHints.entries) {
    if (!entry.value.any(lower.contains)) continue;
    for (final c in categories) {
      if (c.$2.toLowerCase().contains(entry.key)) return c.$1;
    }
  }
  return null;
}
