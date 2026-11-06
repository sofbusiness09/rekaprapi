import 'package:flutter/services.dart';

const _months = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

const _days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

String _two(int n) => n.toString().padLeft(2, '0');

String _grouped(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// 1250000 -> "Rp 1.250.000"
String rupiah(num n) => '${n < 0 ? '-' : ''}Rp ${_grouped(n.abs().round())}';

/// Ringkas untuk sumbu grafik: 1500000 -> "1,5jt", 250000 -> "250rb".
String compact(num v) {
  final a = v.abs();
  String fmt(double x) {
    final s = x.toStringAsFixed(1).replaceAll('.', ',');
    return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
  }

  final String s;
  if (a >= 1e9) {
    s = '${fmt(a / 1e9)}M';
  } else if (a >= 1e6) {
    s = '${fmt(a / 1e6)}jt';
  } else if (a >= 1e3) {
    s = '${fmt(a / 1e3)}rb';
  } else {
    s = a.round().toString();
  }
  return v < 0 ? '-$s' : s;
}

/// "Nov" dari tanggal.
String monthShort(DateTime d) => _months[d.month - 1].substring(0, 3);

/// Angka saja dengan pemisah ribuan, tanpa "Rp".
String thousands(num n) => _grouped(n.round());

/// "1.250.000" -> 1250000 (null bila kosong).
int? parseAmount(String s) {
  final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : int.tryParse(digits);
}

/// Memberi pemisah ribuan saat mengetik jumlah.
class ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    final digits = next.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final text = _grouped(int.parse(digits));
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Format yang diterima kolom `date` Postgres.
String ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

DateTime parseYmd(String s) => DateTime.parse(s);

String dateId(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// "3 Nov 2026 14:05"
String timeId(DateTime d) =>
    '${d.day} ${_months[d.month - 1].substring(0, 3)} ${d.year} ${_two(d.hour)}:${_two(d.minute)}';

/// "14:05"
String clockId(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

/// "3 November 2026, 14:05" bila jam diketahui, selain itu hanya tanggalnya.
String dateTimeId(DateTime date, [DateTime? at]) =>
    at == null ? dateId(date) : '${dateId(date)}, ${clockId(at)}';

/// "Hari ini", "Kemarin", atau "Senin, 3 Nov".
String dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Hari ini';
  if (diff == 1) return 'Kemarin';
  final yearPart = d.year == now.year ? '' : ' ${d.year}';
  return '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1].substring(0, 3)}$yearPart';
}

String monthId(DateTime d) => '${_months[d.month - 1]} ${d.year}';

DateTime firstOfMonth(DateTime d) => DateTime(d.year, d.month);

DateTime lastOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);
