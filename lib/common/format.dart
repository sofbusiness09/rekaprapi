import 'package:flutter/services.dart';

import 'currency.dart';
import 'privacy.dart';
import '../l10n/l10n.dart';

const _monthsId = [
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

const _monthsEn = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _daysId = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu'
];
const _daysEn = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

bool get _en => languageController.language == AppLanguage.en;
List<String> get _months => _en ? _monthsEn : _monthsId;
List<String> get _days => _en ? _daysEn : _daysId;

String _two(int n) => n.toString().padLeft(2, '0');

String _grouped(int n) => groupDigits(n);

/// Jumlah dengan simbol mata uang pembukuan aktif: 1250000 -> "Rp 1.250.000"
/// (atau "$1,250,000" untuk USD). Namanya tetap rupiah() karena dipakai di banyak tempat.
/// Bila nominal disembunyikan (ikon mata), hasilnya "Rp •••••".
String rupiah(num n) =>
    privacyController.hidden ? maskedMoney() : formatMoney(n);

/// Ringkas untuk sumbu grafik: 1500000 -> "1,5jt", 250000 -> "250rb".
String compact(num v) {
  if (privacyController.hidden) return '•••';
  final a = v.abs();
  // Bahasa Inggris: 1.5M dan 250K; Indonesia: 1,5jt dan 250rb.
  final dec = _en ? '.' : ',';
  String fmt(double x) {
    final s = x.toStringAsFixed(1).replaceAll('.', dec);
    return s.endsWith('${dec}0') ? s.substring(0, s.length - 2) : s;
  }

  final String s;
  if (a >= 1e9) {
    s = '${fmt(a / 1e9)}${_en ? 'B' : 'M'}';
  } else if (a >= 1e6) {
    s = '${fmt(a / 1e6)}${_en ? 'M' : 'jt'}';
  } else if (a >= 1e3) {
    s = '${fmt(a / 1e3)}${_en ? 'K' : 'rb'}';
  } else {
    s = a.round().toString();
  }
  return v < 0 ? '-$s' : s;
}

/// "Nov" dari tanggal.
String monthShort(DateTime d) => _months[d.month - 1].substring(0, 3);

/// Angka saja dengan pemisah ribuan mata uang aktif, tanpa simbol.
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

/// "3 November 2026" atau, dalam Bahasa Inggris, "November 3, 2026".
String dateId(DateTime d) => _en
    ? '${_months[d.month - 1]} ${d.day}, ${d.year}'
    : '${d.day} ${_months[d.month - 1]} ${d.year}';

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
  if (diff == 0) return _en ? 'Today' : 'Hari ini';
  if (diff == 1) return _en ? 'Yesterday' : 'Kemarin';
  final yearPart = d.year == now.year ? '' : ' ${d.year}';
  return '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1].substring(0, 3)}$yearPart';
}

String monthId(DateTime d) => '${_months[d.month - 1]} ${d.year}';

DateTime firstOfMonth(DateTime d) => DateTime(d.year, d.month);

DateTime lastOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);
