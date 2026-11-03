import 'package:supabase_flutter/supabase_flutter.dart';

import '../cash/cash_repository.dart' show SaleDetail;
import '../common/format.dart';
import 'debt_models.dart';

/// Semua perubahan utang piutang lewat fungsi database (RPC) supaya kas
/// ikut tercatat/berubah dalam satu transaksi. Klien tidak menulis tabel utang langsung.
class DebtRepository {
  DebtRepository(this.businessId);

  final String businessId;
  SupabaseClient get _db => Supabase.instance.client;
  String get _uid => _db.auth.currentUser!.id;

  Future<List<Contact>> contacts() async {
    final rows = await _db
        .from('contacts')
        .select(Contact.columns)
        .eq('business_id', businessId)
        .isFilter('deleted_at', null)
        .order('name');
    return rows.map(Contact.fromMap).toList();
  }

  Future<String> addContact(String name, String? phone) async {
    final row = await _db
        .from('contacts')
        .insert({
          'business_id': businessId,
          'name': name.trim(),
          'phone': _clean(phone),
          'created_by': _uid,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Menambah kontak dengan data lengkap; mengembalikan id-nya.
  Future<String> createContact({
    required String name,
    String? phone,
    String? address,
    String? note,
  }) async {
    final row = await _db
        .from('contacts')
        .insert({
          'business_id': businessId,
          'name': name.trim(),
          'phone': _clean(phone),
          'address': _clean(address),
          'note': _clean(note),
          'created_by': _uid,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// Semua anggota boleh mengubah data kontak (nomor telepon, alamat, dsb).
  Future<void> updateContact(
    String id, {
    required String name,
    String? phone,
    String? address,
    String? note,
  }) async {
    final rows = await _db
        .from('contacts')
        .update({
          'name': name.trim(),
          'phone': _clean(phone),
          'address': _clean(address),
          'note': _clean(note),
        })
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) {
      throw const PostgrestException(
          message: 'Kontak tidak ditemukan atau tidak bisa diubah.');
    }
  }

  /// Hanya Pemilik/Admin, dan hanya bila tidak ada utang piutang yang belum lunas.
  Future<void> deleteContact(String id) =>
      _db.rpc('delete_contact', params: {'p_contact': id});

  Future<List<Debt>> debts() async {
    final rows = await _db
        .from('debt_balances')
        .select()
        .eq('business_id', businessId)
        .order('due_date', ascending: true, nullsFirst: false)
        .order('created_at', ascending: false);
    return rows.map(Debt.fromMap).toList();
  }

  Future<Debt?> debt(String id) async {
    final row =
        await _db.from('debt_balances').select().eq('id', id).maybeSingle();
    return row == null ? null : Debt.fromMap(row);
  }

  Future<List<Payment>> payments(String debtId) async {
    final rows = await _db
        .from('debt_payments')
        .select(
            'id, debt_id, amount, paid_on, note, created_by, created_at, method, offset_group')
        .eq('debt_id', debtId)
        .isFilter('deleted_at', null)
        .order('paid_on')
        .order('created_at');
    return rows.map(Payment.fromMap).toList();
  }

  /// Transaksi kredit (barang dijual/dibeli secara hutang, uang belum berpindah)
  /// pada rentang tanggal. Dipakai agar tampil di daftar Kas.
  Future<List<Debt>> creditEntries(DateTime from, DateTime to) async {
    final rows = await _db
        .from('debt_balances')
        .select()
        .eq('business_id', businessId)
        .eq('cash_moved', false)
        .gte('debt_date', ymd(from))
        .lte('debt_date', ymd(to))
        .order('debt_date', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(Debt.fromMap).toList();
  }

  /// Riwayat satu kontak: semua catatan (piutang dan utang) beserta pembayarannya.
  Future<Ledger> ledger(String contactId) async {
    final debtRows = await _db
        .from('debt_balances')
        .select()
        .eq('business_id', businessId)
        .eq('contact_id', contactId);
    final debts = debtRows.map(Debt.fromMap).toList();
    if (debts.isEmpty) return Ledger(debts, const []);

    final payRows = await _db
        .from('debt_payments')
        .select(
            'id, debt_id, amount, paid_on, note, created_by, created_at, method, offset_group')
        .inFilter('debt_id', [for (final d in debts) d.id]).isFilter(
            'deleted_at', null);
    return Ledger(debts, payRows.map(Payment.fromMap).toList());
  }

  /// Saldo bersih kontak: positif = kontak berutang kepada Anda, negatif = Anda
  /// berutang kepadanya (Anda diberi utang/modal).
  Future<int> contactNet(String contactId) async {
    final rows = await _db
        .from('debt_balances')
        .select('kind, remaining')
        .eq('business_id', businessId)
        .eq('contact_id', contactId)
        .gt('remaining', 0);
    var net = 0;
    for (final r in rows) {
      final v = (r['remaining'] as num).toInt();
      net += r['kind'] == 'receivable' ? v : -v;
    }
    return net;
  }

  /// Uang yang benar-benar berpindah. [receive] true = Anda menerima uang dari kontak:
  /// melunasi piutang lebih dulu, kelebihannya menjadi utang. false = Anda memberi
  /// uang: melunasi utang lebih dulu, kelebihannya menjadi piutang.
  Future<void> transfer(
    String contactId, {
    required bool receive,
    required int amount,
    required DateTime paidOn,
    String? note,
  }) async {
    await _db.rpc('contact_transfer', params: {
      'p_business': businessId,
      'p_contact': contactId,
      'p_direction': receive ? 'receive' : 'give',
      'p_amount': amount,
      'p_paid_on': ymd(paidOn),
      'p_note': _clean(note),
    });
  }

  /// Melunasi saldo bersih kontak (terima bila ia berutang, bayar bila Anda berutang).
  Future<void> settle(String contactId,
      {required DateTime paidOn, String? note}) async {
    await _db.rpc('settle_contact', params: {
      'p_business': businessId,
      'p_contact': contactId,
      'p_paid_on': ymd(paidOn),
      'p_note': _clean(note),
    });
  }

  /// Semua cicilan usaha (untuk ekspor): {debt_id, amount, paid_on, note, created_by}.
  Future<List<Map<String, dynamic>>> allPayments() async {
    final rows = await _db
        .from('debt_payments')
        .select('debt_id, amount, paid_on, note, created_by, method')
        .eq('business_id', businessId)
        .isFilter('deleted_at', null)
        .order('paid_on');
    return [for (final r in rows) Map<String, dynamic>.from(r)];
  }

  Future<void> create({
    required String contactId,
    required String kind,
    required int amount,
    required bool cashMoved,
    required DateTime debtDate,
    DateTime? dueDate,
    String? note,
    SaleDetail? sale,
  }) async {
    await _db.rpc('create_debt', params: {
      'p_business': businessId,
      'p_contact': contactId,
      'p_kind': kind,
      'p_amount': amount,
      'p_cash_moved': cashMoved,
      'p_debt_date': ymd(debtDate),
      'p_due_date': dueDate == null ? null : ymd(dueDate),
      'p_note': _clean(note),
      'p_is_sale': sale != null,
      'p_cost': sale?.cost ?? 0,
      'p_discount': sale?.discount ?? 0,
      'p_fee': sale?.fee ?? 0,
    });
  }

  Future<void> update(
    String id, {
    required String contactId,
    required int amount,
    required DateTime debtDate,
    DateTime? dueDate,
    String? note,
  }) async {
    await _db.rpc('update_debt', params: {
      'p_debt': id,
      'p_contact': contactId,
      'p_amount': amount,
      'p_debt_date': ymd(debtDate),
      'p_due_date': dueDate == null ? null : ymd(dueDate),
      'p_note': _clean(note),
    });
  }

  Future<void> remove(String id) =>
      _db.rpc('delete_debt', params: {'p_debt': id});

  Future<void> addPayment(String debtId,
      {required int amount, required DateTime paidOn, String? note}) async {
    await _db.rpc('add_debt_payment', params: {
      'p_debt': debtId,
      'p_amount': amount,
      'p_paid_on': ymd(paidOn),
      'p_note': _clean(note),
    });
  }

  Future<void> updatePayment(String id,
      {required int amount, required DateTime paidOn, String? note}) async {
    await _db.rpc('update_debt_payment', params: {
      'p_payment': id,
      'p_amount': amount,
      'p_paid_on': ymd(paidOn),
      'p_note': _clean(note),
    });
  }

  Future<void> removePayment(String id) =>
      _db.rpc('delete_debt_payment', params: {'p_payment': id});

  String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
