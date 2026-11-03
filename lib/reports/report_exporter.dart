import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:file_saver/file_saver.dart';

import '../cash/cash_models.dart';
import '../cash/cash_repository.dart';
import '../common/format.dart';
import '../debts/debt_models.dart';
import '../debts/debt_repository.dart';

class _Data {
  _Data({
    required this.summary,
    required this.cash,
    required this.categories,
    required this.names,
    required this.byCategory,
    required this.debts,
    required this.contacts,
    required this.payments,
  });

  final Summary summary;
  final List<CashTx> cash;
  final Map<String, String> categories; // id -> nama
  final Map<String, String> names; // user id -> nama
  final List<Map<String, dynamic>> byCategory;
  final List<Debt> debts;
  final Map<String, String> contacts; // id -> nama
  final List<Map<String, dynamic>> payments;
}

/// Membuat berkas Excel (.xlsx) atau CSV dari data usaha dan menyimpannya/mengunduhnya.
/// Untuk Google Sheets: unggah berkas Excel ke Google Drive lalu buka dengan Google Sheets.
class ReportExporter {
  ReportExporter({
    required this.businessName,
    required this.cash,
    required this.debts,
  });

  final String businessName;
  final CashRepository cash;
  final DebtRepository debts;

  Future<_Data> _gather(DateTime from, DateTime to) async {
    final r = await Future.wait([
      cash.summary(from, to),
      cash.listAll(from, to),
      cash.categories(),
      cash.memberNames(),
      cash.byCategory(from, to),
      debts.debts(),
      debts.contacts(),
      debts.allPayments(),
    ]);
    return _Data(
      summary: r[0] as Summary,
      cash: r[1] as List<CashTx>,
      categories: {for (final c in r[2] as List<Category>) c.id: c.name},
      names: r[3] as Map<String, String>,
      byCategory: r[4] as List<Map<String, dynamic>>,
      debts: r[5] as List<Debt>,
      contacts: {for (final c in r[6] as List<Contact>) c.id: c.name},
      payments: r[7] as List<Map<String, dynamic>>,
    );
  }

  String _fileBase(DateTime from, DateTime to) {
    final safe = businessName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return 'RekapRapi_${safe.isEmpty ? 'usaha' : safe}_${ymd(from)}_${ymd(to)}';
  }

  String _who(_Data d, String? uid) =>
      (uid == null ? null : d.names[uid]) ?? '-';

  Future<void> exportXlsx(DateTime from, DateTime to) async {
    final d = await _gather(from, to);
    final excel = Excel.createExcel();
    excel.rename('Sheet1', 'Ringkasan');

    void add(String sheet, List<Object?> row) {
      excel[sheet].appendRow([for (final v in row) _cell(v)]);
    }

    // Ringkasan
    add('Ringkasan', ['Usaha', businessName]);
    add('Ringkasan', ['Periode', '${ymd(from)} s/d ${ymd(to)}']);
    add('Ringkasan', ['Total kas masuk', d.summary.totalIn]);
    add('Ringkasan', ['Total kas keluar', d.summary.totalOut]);
    add('Ringkasan',
        ['Selisih periode', d.summary.totalIn - d.summary.totalOut]);
    add('Ringkasan', ['Total penjualan (bersih)', d.summary.salesTotal]);
    add('Ringkasan', ['Keuntungan penjualan', d.summary.profit]);
    add('Ringkasan', ['Saldo kas saat ini', d.summary.balance]);
    add('Ringkasan', ['Piutang belum lunas', d.summary.receivableOpen]);
    add('Ringkasan', ['Utang belum lunas', d.summary.payableOpen]);
    add('Ringkasan', []);
    add('Ringkasan', ['Rekap per kategori']);
    add('Ringkasan', ['Kategori', 'Jenis', 'Jumlah transaksi', 'Total']);
    for (final c in d.byCategory) {
      add('Ringkasan', [
        c['category_name'],
        c['type'] == 'in' ? 'Masuk' : 'Keluar',
        (c['tx_count'] as num).toInt(),
        (c['total'] as num).toInt(),
      ]);
    }

    // Kas
    add('Kas', [
      'Tanggal',
      'Jenis',
      'Kategori',
      'Jumlah',
      'Catatan',
      'Dicatat oleh',
      'Sumber',
      'Total Penjualan',
      'Harga Modal',
      'Diskon',
      'Biaya Tambahan',
      'Keuntungan'
    ]);
    for (final t in d.cash) {
      add('Kas', [
        ymd(t.date),
        t.isIn ? 'Masuk' : 'Keluar',
        d.categories[t.categoryId] ?? 'Tanpa kategori',
        t.amount,
        t.note ?? '',
        _who(d, t.createdBy),
        t.isAuto ? 'Otomatis (utang piutang)' : 'Manual',
        if (t.isSale) ...[
          t.saleTotal,
          t.costAmount,
          t.discountAmount,
          t.extraFee,
          t.profit,
        ],
      ]);
    }

    // Piutang dan Utang (kondisi saat ini)
    for (final kind in const ['receivable', 'payable']) {
      final sheet = kind == 'receivable' ? 'Piutang' : 'Utang';
      add(sheet, [
        'Tanggal',
        'Kontak',
        'Jumlah',
        'Dibayar',
        'Sisa',
        'Jatuh tempo',
        'Status',
        'Catatan',
        'Dicatat oleh'
      ]);
      for (final x in d.debts.where((x) => x.kind == kind)) {
        add(sheet, [
          ymd(x.debtDate),
          d.contacts[x.contactId] ?? '-',
          x.amount,
          x.paid,
          x.remaining,
          x.dueDate == null ? '' : ymd(x.dueDate!),
          x.settled ? 'Lunas' : (x.overdue ? 'Lewat tempo' : 'Belum lunas'),
          x.note ?? '',
          _who(d, x.createdBy),
        ]);
      }
    }

    // Cicilan pada periode
    final byDebt = {for (final x in d.debts) x.id: x};
    add('Cicilan',
        ['Tanggal', 'Kontak', 'Jenis', 'Jumlah', 'Catatan', 'Dicatat oleh']);
    for (final p in d.payments) {
      final date = parseYmd(p['paid_on'] as String);
      if (p['method'] == 'offset') continue; // kompensasi bukan uang berpindah
      final debt = byDebt[p['debt_id']];
      if (debt == null || date.isBefore(from) || date.isAfter(to)) continue;
      add('Cicilan', [
        ymd(date),
        d.contacts[debt.contactId] ?? '-',
        debt.isReceivable ? 'Pembayaran piutang' : 'Pembayaran utang',
        (p['amount'] as num).toInt(),
        p['note'] ?? '',
        _who(d, p['created_by'] as String?),
      ]);
    }

    final bytes = excel.encode();
    if (bytes == null) throw StateError('Gagal membuat berkas Excel.');
    await FileSaver.instance.saveFile(
      name: _fileBase(from, to),
      bytes: Uint8List.fromList(bytes),
      ext: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }

  /// CSV berisi transaksi kas saja. Diberi BOM agar Excel membaca UTF-8 dengan benar.
  Future<void> exportCsv(DateTime from, DateTime to) async {
    final d = await _gather(from, to);
    final lines = <String>[
      _csv([
        'Tanggal',
        'Jenis',
        'Kategori',
        'Jumlah',
        'Catatan',
        'Dicatat oleh',
        'Sumber',
        'Total Penjualan',
        'Harga Modal',
        'Diskon',
        'Biaya Tambahan',
        'Keuntungan'
      ]),
      for (final t in d.cash)
        _csv([
          ymd(t.date),
          t.isIn ? 'Masuk' : 'Keluar',
          d.categories[t.categoryId] ?? 'Tanpa kategori',
          t.amount,
          t.note ?? '',
          _who(d, t.createdBy),
          t.isAuto ? 'Otomatis (utang piutang)' : 'Manual',
          if (t.isSale) ...[
            t.saleTotal,
            t.costAmount,
            t.discountAmount,
            t.extraFee,
            t.profit,
          ],
        ]),
    ];
    final bytes = utf8.encode('﻿${lines.join('\r\n')}\r\n');
    await FileSaver.instance.saveFile(
      name: _fileBase(from, to),
      bytes: Uint8List.fromList(bytes),
      ext: 'csv',
      mimeType: MimeType.csv,
    );
  }

  CellValue? _cell(Object? v) {
    if (v == null) return null;
    if (v is int) return IntCellValue(v);
    return TextCellValue(v.toString());
  }

  String _csv(List<Object?> cells) => cells.map((c) {
        final s = (c ?? '').toString();
        // Cegah rumus tak sengaja saat dibuka di spreadsheet.
        final safe = RegExp(r'^[=+\-@]').hasMatch(s) && c is! int ? "'$s" : s;
        return (safe.contains(',') || safe.contains('"') || safe.contains('\n'))
            ? '"${safe.replaceAll('"', '""')}"'
            : safe;
      }).join(',');
}
