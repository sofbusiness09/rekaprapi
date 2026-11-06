import '../common/format.dart';

class Category {
  const Category(this.id, this.name, this.type, this.isSystem,
      {this.isSale = false});

  final String id;
  final String name;

  /// 'in' | 'out'
  final String type;

  /// Kategori sistem dipakai sinkron utang piutang; tidak untuk input manual.
  final bool isSystem;

  /// Kategori penjualan: transaksi di dalamnya punya harga modal, diskon,
  /// biaya tambahan, dan keuntungan.
  final bool isSale;

  factory Category.fromMap(Map<String, dynamic> m) => Category(
        m['id'] as String,
        m['name'] as String,
        m['type'] as String,
        m['is_system'] as bool,
        isSale: (m['is_sale'] as bool?) ?? false,
      );
}

class CashTx {
  const CashTx({
    required this.id,
    required this.type,
    required this.amount,
    required this.date,
    this.note,
    this.categoryId,
    this.debtId,
    this.debtPaymentId,
    this.createdBy,
    this.isSale = false,
    this.costAmount = 0,
    this.discountAmount = 0,
    this.extraFee = 0,
    this.createdAt,
  });

  final String id;
  final String type;

  /// Uang yang benar-benar masuk/keluar. Untuk penjualan:
  /// Total Penjualan - Diskon + Biaya Tambahan.
  final int amount;
  final DateTime date;
  final String? note;
  final String? categoryId;
  final String? debtId;
  final String? debtPaymentId;
  final String? createdBy;
  final bool isSale;
  final int costAmount;
  final int discountAmount;
  final int extraFee;

  /// Saat dicatat (jam), dipakai mengurutkan transaksi dalam satu hari.
  final DateTime? createdAt;

  bool get isIn => type == 'in';

  /// Dibuat otomatis oleh utang piutang; tidak bisa diubah langsung.
  bool get isAuto => debtId != null || debtPaymentId != null;

  /// Total Penjualan sebelum diskon dan tanpa biaya tambahan.
  int get saleTotal => amount + discountAmount - extraFee;

  /// Keuntungan = uang diterima - Harga Modal. Biaya tambahan ikut sebagai pemasukan.
  int get profit => amount - costAmount;

  /// Kolom yang dibaca dari tabel cash_transactions.
  static const columns =
      'id, type, amount, note, txn_date, category_id, debt_id, debt_payment_id, created_by, '
      'is_sale, cost_amount, discount_amount, extra_fee, created_at';

  factory CashTx.fromMap(Map<String, dynamic> m) => CashTx(
        id: m['id'] as String,
        type: m['type'] as String,
        amount: (m['amount'] as num).toInt(),
        date: parseYmd(m['txn_date'] as String),
        note: m['note'] as String?,
        categoryId: m['category_id'] as String?,
        debtId: m['debt_id'] as String?,
        debtPaymentId: m['debt_payment_id'] as String?,
        createdBy: m['created_by'] as String?,
        isSale: (m['is_sale'] as bool?) ?? false,
        costAmount: ((m['cost_amount'] as num?) ?? 0).toInt(),
        discountAmount: ((m['discount_amount'] as num?) ?? 0).toInt(),
        extraFee: ((m['extra_fee'] as num?) ?? 0).toInt(),
        createdAt: m['created_at'] == null
            ? null
            : DateTime.parse(m['created_at'] as String).toLocal(),
      );
}

class Summary {
  const Summary({
    required this.totalIn,
    required this.totalOut,
    required this.balance,
    required this.receivableOpen,
    required this.payableOpen,
    this.salesTotal = 0,
    this.profit = 0,
    this.incomeSales = 0,
    this.incomeOther = 0,
    this.incomeTotal = 0,
    this.expenseCost = 0,
    this.expenseOther = 0,
    this.expenseCredit = 0,
    this.expenseTotal = 0,
    this.net = 0,
  });

  final int totalIn;
  final int totalOut;
  final int balance;
  final int receivableOpen;
  final int payableOpen;

  /// Total penjualan bersih pada periode (setelah diskon, tanpa biaya tambahan).
  final int salesTotal;

  /// Keuntungan penjualan pada periode (penjualan - modal).
  final int profit;

  // Pembukuan Usaha: Pemasukan = penjualan + penjualan lainnya; Pengeluaran = modal
  // barang + pengeluaran biasa (lunas dan hutang); Laba = Pemasukan - Pengeluaran.
  final int incomeSales;
  final int incomeOther;
  final int incomeTotal;
  final int expenseCost;
  final int expenseOther;

  /// Bagian pengeluaran biasa yang berstatus hutang (sudah termasuk di [expenseOther]).
  final int expenseCredit;
  final int expenseTotal;

  /// Laba (positif) atau rugi (negatif) periode.
  final int net;

  factory Summary.fromMap(Map<String, dynamic> m) => Summary(
        totalIn: (m['total_in'] as num).toInt(),
        totalOut: (m['total_out'] as num).toInt(),
        balance: (m['balance'] as num).toInt(),
        receivableOpen: (m['receivable_open'] as num).toInt(),
        payableOpen: (m['payable_open'] as num).toInt(),
        salesTotal: ((m['sales_total'] as num?) ?? 0).toInt(),
        profit: ((m['profit'] as num?) ?? 0).toInt(),
        incomeSales: ((m['income_sales'] as num?) ?? 0).toInt(),
        incomeOther: ((m['income_other'] as num?) ?? 0).toInt(),
        incomeTotal: ((m['income_total'] as num?) ?? 0).toInt(),
        expenseCost: ((m['expense_cost'] as num?) ?? 0).toInt(),
        expenseOther: ((m['expense_other'] as num?) ?? 0).toInt(),
        expenseCredit: ((m['expense_credit'] as num?) ?? 0).toInt(),
        expenseTotal: ((m['expense_total'] as num?) ?? 0).toInt(),
        net: ((m['net'] as num?) ?? 0).toInt(),
      );
}

/// Satu hari untuk grafik: kas masuk, kas keluar, dan keuntungan penjualan.
class DailyPoint {
  const DailyPoint(this.day, this.cashIn, this.cashOut, this.profit);

  final DateTime day;
  final int cashIn;
  final int cashOut;
  final int profit;

  factory DailyPoint.fromMap(Map<String, dynamic> m) => DailyPoint(
        parseYmd(m['day'] as String),
        (m['cash_in'] as num).toInt(),
        (m['cash_out'] as num).toInt(),
        (m['profit'] as num).toInt(),
      );
}

/// Satu aktivitas perputaran uang untuk Beranda: transaksi kas (termasuk kas otomatis
/// dari pelunasan dan pinjaman uang) atau transaksi hutang yang uangnya belum berpindah.
class Activity {
  const Activity({
    required this.kind,
    required this.refId,
    required this.date,
    required this.flow,
    required this.amount,
    required this.title,
    required this.isAuto,
    required this.isSale,
    this.debtId,
    this.contactName,
    this.note,
    this.profit,
    this.remaining,
    this.createdBy,
  });

  /// 'cash' | 'credit'
  final String kind;
  final String refId;
  final String? debtId;
  final DateTime date;

  /// 'in' | 'out'
  final String flow;
  final int amount;
  final String title;
  final String? contactName;
  final String? note;
  final bool isAuto;
  final bool isSale;
  final int? profit;

  /// Hanya untuk transaksi hutang: sisa yang belum dibayar.
  final int? remaining;
  final String? createdBy;

  bool get isCredit => kind == 'credit';
  bool get isIn => flow == 'in';
  bool get settled => (remaining ?? 0) <= 0;

  /// Jenis aktivitas, untuk filter di Beranda. Kategori sistem tidak bisa diubah
  /// namanya, jadi nama kategori aman dipakai untuk membedakan pelunasan dan pinjaman.
  ActivityType get type {
    if (isCredit) return ActivityType.credit;
    if (isAuto) {
      return (title == 'Pelunasan Piutang' || title == 'Pembayaran Utang')
          ? ActivityType.payment
          : ActivityType.loan;
    }
    return isIn ? ActivityType.cashIn : ActivityType.cashOut;
  }

  factory Activity.fromMap(Map<String, dynamic> m) => Activity(
        kind: m['kind'] as String,
        refId: m['ref_id'] as String,
        debtId: m['debt_id'] as String?,
        date: parseYmd(m['txn_date'] as String),
        flow: m['flow'] as String,
        amount: (m['amount'] as num).toInt(),
        title: m['title'] as String,
        contactName: m['contact_name'] as String?,
        note: m['note'] as String?,
        isAuto: (m['is_auto'] as bool?) ?? false,
        isSale: (m['is_sale'] as bool?) ?? false,
        profit: (m['profit'] as num?)?.toInt(),
        remaining: (m['remaining'] as num?)?.toInt(),
        createdBy: m['created_by'] as String?,
      );
}

/// Jenis aktivitas uang pada Beranda.
enum ActivityType {
  /// Kas masuk biasa (termasuk penjualan lunas).
  cashIn,

  /// Kas keluar biasa.
  cashOut,

  /// Transaksi hutang: barang dijual/dibeli kredit, uang belum berpindah.
  credit,

  /// Pelunasan piutang atau pembayaran utang (kas otomatis).
  payment,

  /// Pemberian hutang atau penerimaan utang/modal berupa uang (kas otomatis).
  loan,
}
