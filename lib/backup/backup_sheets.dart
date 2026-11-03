import '../cash/cash_models.dart';
import '../common/format.dart';
import '../debts/debt_models.dart';

/// Satu lembar yang dikirim ke Google Sheet. Baris pertama adalah judul kolom.
class BackupSheet {
  const BackupSheet(this.name, this.rows, {this.textColumns = const []});

  final String name;
  final List<List<Object?>> rows;

  /// Kolom (mulai 0) yang dipaksa berupa teks di Google Sheet: nama, catatan, telepon.
  /// Mencegah nomor berawalan 0 kehilangan angka nol dan teks berawalan "=" menjadi rumus.
  final List<int> textColumns;

  /// Jumlah baris data tanpa judul.
  int get dataRows => rows.isEmpty ? 0 : rows.length - 1;

  Map<String, dynamic> toJson() => {
        'name': name,
        'rows': rows,
        'textColumns': textColumns,
      };
}

/// Semua data usaha yang masuk backup.
class BackupData {
  const BackupData({
    required this.businessName,
    required this.generatedAt,
    required this.generatedBy,
    required this.summary,
    required this.cash,
    required this.categories,
    required this.memberNames,
    required this.debts,
    required this.contacts,
    required this.payments,
  });

  final String businessName;
  final DateTime generatedAt;
  final String generatedBy;

  /// Ringkasan sepanjang waktu.
  final Summary summary;
  final List<CashTx> cash;
  final Map<String, String> categories; // id -> nama
  final Map<String, String> memberNames; // id pengguna -> nama
  final List<Debt> debts;
  final List<Contact> contacts;

  /// Baris debt_payments mentah: debt_id, amount, paid_on, note, created_by, method.
  final List<Map<String, dynamic>> payments;
}

String _dateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${ymd(d)} ${two(d.hour)}:${two(d.minute)}';
}

/// Menyusun semua lembar backup dari data usaha. Fungsi murni agar mudah diuji.
List<BackupSheet> buildBackupSheets(BackupData d) {
  String who(String? uid) => (uid == null ? null : d.memberNames[uid]) ?? '-';
  final contactName = {for (final c in d.contacts) c.id: c.name};
  final debtById = {for (final x in d.debts) x.id: x};

  String status(Debt x) =>
      x.settled ? 'Lunas' : (x.overdue ? 'Lewat tempo' : 'Belum lunas');

  String debtKind(Debt x) {
    if (x.isSale) return 'Penjualan';
    return x.cashMoved ? 'Uang' : 'Barang/kredit';
  }

  // --- Info ---
  final info = BackupSheet(
    'Info',
    [
      ['Keterangan', 'Nilai'],
      ['Usaha', d.businessName],
      ['Waktu backup', _dateTime(d.generatedAt)],
      ['Dibackup oleh', d.generatedBy],
      ['Jumlah transaksi kas', d.cash.length],
      ['Jumlah catatan utang piutang', d.debts.length],
      ['Jumlah kontak', d.contacts.length],
      [
        'Catatan',
        'Setiap backup menimpa isi semua lembar ini dengan data terbaru. '
            'Simpan catatan atau rumus pribadi Anda di lembar lain.'
      ],
    ],
    textColumns: const [0, 1],
  );

  // --- Ringkasan ---
  final s = d.summary;
  final summary = BackupSheet(
    'Ringkasan',
    [
      ['Keterangan', 'Nilai'],
      ['Saldo kas saat ini', s.balance],
      ['Total kas masuk (semua waktu)', s.totalIn],
      ['Total kas keluar (semua waktu)', s.totalOut],
      ['Total penjualan bersih (semua waktu)', s.salesTotal],
      ['Keuntungan penjualan (semua waktu)', s.profit],
      ['Piutang belum lunas', s.receivableOpen],
      ['Utang belum lunas', s.payableOpen],
    ],
    textColumns: const [0],
  );

  // --- Kas ---
  final cash = BackupSheet(
    'Kas',
    [
      [
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
        'Keuntungan',
      ],
      for (final t in d.cash)
        [
          ymd(t.date),
          t.isIn ? 'Masuk' : 'Keluar',
          d.categories[t.categoryId] ?? 'Tanpa kategori',
          t.amount,
          t.note ?? '',
          who(t.createdBy),
          t.isAuto ? 'Otomatis (utang piutang)' : 'Manual',
          t.isSale ? t.saleTotal : '',
          t.isSale ? t.costAmount : '',
          t.isSale ? t.discountAmount : '',
          t.isSale ? t.extraFee : '',
          t.isSale ? t.profit : '',
        ],
    ],
    textColumns: const [1, 2, 4, 5, 6],
  );

  // --- Piutang dan Utang ---
  BackupSheet debtSheet(String name, bool receivable) {
    final list = d.debts.where((x) => x.isReceivable == receivable).toList()
      ..sort((a, b) => a.debtDate.compareTo(b.debtDate));
    return BackupSheet(
      name,
      [
        [
          'Tanggal',
          'Kontak',
          'Jumlah',
          'Dibayar',
          'Sisa',
          'Jatuh tempo',
          'Status',
          'Catatan',
          'Dicatat oleh',
          'Jenis catatan',
          'Harga Modal',
          'Diskon',
          'Biaya Tambahan',
          'Keuntungan',
        ],
        for (final x in list)
          [
            ymd(x.debtDate),
            contactName[x.contactId] ?? '-',
            x.amount,
            x.paid,
            x.remaining,
            x.dueDate == null ? '' : ymd(x.dueDate!),
            status(x),
            x.note ?? '',
            who(x.createdBy),
            debtKind(x),
            x.isSale ? x.costAmount : '',
            x.isSale ? x.discountAmount : '',
            x.isSale ? x.extraFee : '',
            x.isSale ? x.profit : '',
          ],
      ],
      textColumns: const [1, 6, 7, 8, 9],
    );
  }

  // --- Pembayaran ---
  final payments = [
    ...d.payments
  ]..sort((a, b) => (a['paid_on'] as String).compareTo(b['paid_on'] as String));
  final paymentSheet = BackupSheet(
    'Pembayaran',
    [
      [
        'Tanggal',
        'Kontak',
        'Jenis',
        'Jumlah',
        'Metode',
        'Catatan',
        'Dicatat oleh'
      ],
      for (final p in payments)
        if (debtById[p['debt_id']] != null)
          [
            p['paid_on'] as String,
            contactName[debtById[p['debt_id']]!.contactId] ?? '-',
            debtById[p['debt_id']]!.isReceivable ? 'Piutang' : 'Utang',
            (p['amount'] as num).toInt(),
            p['method'] == 'offset' ? 'Kompensasi' : 'Uang',
            (p['note'] as String?) ?? '',
            who(p['created_by'] as String?),
          ],
    ],
    textColumns: const [1, 2, 4, 5, 6],
  );

  // --- Kontak ---
  int sumRemaining(String id, bool receivable) => d.debts
      .where((x) => x.contactId == id && x.isReceivable == receivable)
      .fold(0, (sum, x) => sum + x.remaining);
  final contacts = BackupSheet(
    'Kontak',
    [
      [
        'Nama',
        'Telepon',
        'Alamat',
        'Catatan',
        'Piutang',
        'Utang',
        'Saldo bersih'
      ],
      for (final c in d.contacts)
        [
          c.name,
          c.phone ?? '',
          c.address ?? '',
          c.note ?? '',
          sumRemaining(c.id, true),
          sumRemaining(c.id, false),
          sumRemaining(c.id, true) - sumRemaining(c.id, false),
        ],
    ],
    textColumns: const [0, 1, 2, 3],
  );

  return [
    info,
    summary,
    cash,
    debtSheet('Piutang', true),
    debtSheet('Utang', false),
    paymentSheet,
    contacts,
  ];
}
