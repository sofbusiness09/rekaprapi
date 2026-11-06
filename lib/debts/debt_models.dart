import '../common/format.dart';

class Contact {
  const Contact(this.id, this.name, this.phone, {this.address, this.note});

  final String id;
  final String name;
  final String? phone;
  final String? address;
  final String? note;

  /// Kolom yang dibaca dari tabel contacts.
  static const columns = 'id, name, phone, address, note';

  factory Contact.fromMap(Map<String, dynamic> m) => Contact(
        m['id'] as String,
        m['name'] as String,
        m['phone'] as String?,
        address: m['address'] as String?,
        note: m['note'] as String?,
      );
}

class Debt {
  const Debt({
    required this.id,
    required this.contactId,
    required this.kind,
    required this.amount,
    required this.cashMoved,
    required this.debtDate,
    required this.paid,
    required this.remaining,
    required this.createdAt,
    this.dueDate,
    this.note,
    this.createdBy,
    this.isSale = false,
    this.costAmount = 0,
    this.discountAmount = 0,
    this.extraFee = 0,
  });

  final String id;
  final String contactId;

  /// 'receivable' (piutang) | 'payable' (utang)
  final String kind;
  final int amount;

  /// true = uang berpindah saat dicatat (mis. meminjamkan uang); false = barang kredit.
  final bool cashMoved;
  final DateTime debtDate;
  final DateTime? dueDate;
  final String? note;
  final String? createdBy;
  final DateTime createdAt;
  final int paid;
  final int remaining;
  final bool isSale;
  final int costAmount;
  final int discountAmount;
  final int extraFee;

  bool get isReceivable => kind == 'receivable';
  bool get settled => remaining <= 0;

  /// Keuntungan penjualan kredit = jumlah - harga modal (biaya tambahan ikut sebagai pemasukan).
  int get profit => amount - costAmount;

  bool get overdue {
    final d = dueDate;
    if (d == null || settled) return false;
    final now = DateTime.now();
    return d.isBefore(DateTime(now.year, now.month, now.day));
  }

  factory Debt.fromMap(Map<String, dynamic> m) => Debt(
        id: m['id'] as String,
        contactId: m['contact_id'] as String,
        kind: m['kind'] as String,
        amount: (m['amount'] as num).toInt(),
        cashMoved: m['cash_moved'] as bool,
        debtDate: parseYmd(m['debt_date'] as String),
        dueDate:
            m['due_date'] == null ? null : parseYmd(m['due_date'] as String),
        note: m['note'] as String?,
        createdBy: m['created_by'] as String?,
        createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
        paid: (m['paid'] as num).toInt(),
        remaining: (m['remaining'] as num).toInt(),
        isSale: (m['is_sale'] as bool?) ?? false,
        costAmount: ((m['cost_amount'] as num?) ?? 0).toInt(),
        discountAmount: ((m['discount_amount'] as num?) ?? 0).toInt(),
        extraFee: ((m['extra_fee'] as num?) ?? 0).toInt(),
      );
}

class Payment {
  const Payment(this.id, this.amount, this.paidOn, this.note, this.createdBy,
      {this.debtId, this.createdAt, this.method = 'cash', this.offsetGroup});

  final String id;
  final int amount;
  final DateTime paidOn;
  final String? note;
  final String? createdBy;
  final String? debtId;
  final DateTime? createdAt;

  /// 'cash' = uang berpindah; 'offset' = dikompensasi dengan catatan arah berlawanan.
  final String method;
  final String? offsetGroup;

  bool get isOffset => method == 'offset';

  factory Payment.fromMap(Map<String, dynamic> m) => Payment(
        m['id'] as String,
        (m['amount'] as num).toInt(),
        parseYmd(m['paid_on'] as String),
        m['note'] as String?,
        m['created_by'] as String?,
        debtId: m['debt_id'] as String?,
        createdAt: m['created_at'] == null
            ? null
            : DateTime.parse(m['created_at'] as String).toLocal(),
        method: (m['method'] as String?) ?? 'cash',
        offsetGroup: m['offset_group'] as String?,
      );
}

/// Satu baris riwayat kontak: catatan utang piutang atau pembayaran.
class LedgerEntry {
  const LedgerEntry.debt(Debt this.debt)
      : payment = null,
        parent = null;
  const LedgerEntry.payment(Payment this.payment, Debt this.parent)
      : debt = null;

  final Debt? debt;
  final Payment? payment;

  /// Catatan tempat pembayaran ini dicatat.
  final Debt? parent;

  bool get isPayment => payment != null;
  bool get isOffset => payment?.isOffset ?? false;

  DateTime get date => isPayment ? payment!.paidOn : debt!.debtDate;

  DateTime get createdAt =>
      isPayment ? (payment!.createdAt ?? payment!.paidOn) : debt!.createdAt;

  int get amount => isPayment ? payment!.amount : debt!.amount;

  /// Dari sisi Anda: true = Anda menerima (uang/barang masuk), false = Anda memberi.
  /// Catatan piutang = memberi; catatan utang = menerima; pembayaran kebalikan arah catatannya.
  bool get receiving {
    if (isPayment) return parent!.isReceivable;
    return !debt!.isReceivable;
  }
}

/// Seluruh catatan satu kontak, piutang dan utang digabung menjadi satu saldo.
class Ledger {
  Ledger(this.debts, this.payments);

  final List<Debt> debts;
  final List<Payment> payments;

  /// Yang masih harus dibayar kontak kepada Anda.
  int get receivable =>
      debts.where((d) => d.isReceivable).fold(0, (s, d) => s + d.remaining);

  /// Yang masih harus Anda bayar kepada kontak (Anda diberi utang/modal).
  int get payable =>
      debts.where((d) => !d.isReceivable).fold(0, (s, d) => s + d.remaining);

  /// Positif = kontak berutang kepada Anda; negatif = Anda berutang kepada kontak.
  int get net => receivable - payable;

  /// Urut dari terbaru: tanggal, lalu waktu dibuat. Kompensasi yang berpasangan
  /// tampil satu kali (sisi piutang).
  List<LedgerEntry> get entries {
    final byId = {for (final d in debts) d.id: d};
    final seenGroups = <String>{};
    final list = <LedgerEntry>[
      for (final d in debts) LedgerEntry.debt(d),
    ];
    final sorted = [...payments]..sort((a, b) {
        // Sisi piutang lebih dulu agar itu yang dipilih untuk pasangan kompensasi.
        final ar = byId[a.debtId]?.isReceivable ?? false;
        final br = byId[b.debtId]?.isReceivable ?? false;
        return ar == br ? 0 : (ar ? -1 : 1);
      });
    for (final p in sorted) {
      final parent = byId[p.debtId];
      if (parent == null) continue;
      final g = p.offsetGroup;
      if (g != null && !seenGroups.add(g)) continue;
      list.add(LedgerEntry.payment(p, parent));
    }
    list.sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }
}
