import 'package:supabase_flutter/supabase_flutter.dart';

import '../common/format.dart';
import 'cash_models.dart';

/// Rincian penjualan yang menyertai transaksi kas masuk.
class SaleDetail {
  const SaleDetail({this.cost = 0, this.discount = 0, this.fee = 0});

  /// Harga modal.
  final int cost;

  /// Diskon (mengurangi keuntungan).
  final int discount;

  /// Biaya tambahan di luar penjualan, mis. ongkir (tidak memengaruhi keuntungan).
  final int fee;
}

/// Akses data kas satu usaha. Hak akses sebenarnya ditegakkan RLS di database;
/// pemeriksaan di antarmuka hanya untuk menyembunyikan tombol.
class CashRepository {
  CashRepository(this.businessId);

  final String businessId;
  SupabaseClient get _db => Supabase.instance.client;
  String get _uid => _db.auth.currentUser!.id;

  Future<List<Category>> categories() async {
    final rows = await _db
        .from('categories')
        .select('id, name, type, is_system, is_sale')
        .eq('business_id', businessId)
        .order('name');
    return rows.map(Category.fromMap).toList();
  }

  /// id pengguna -> nama tampilan, untuk anggota yang terlihat oleh RLS.
  Future<Map<String, String>> memberNames() async {
    final rows = await _db.from('profiles').select('id, display_name, email');
    return {
      for (final r in rows)
        r['id'] as String:
            (r['display_name'] ?? r['email'] ?? 'Anggota') as String,
    };
  }

  Future<List<CashTx>> list(DateTime from, DateTime to) async {
    final rows = await _db
        .from('cash_transactions')
        .select(CashTx.columns)
        .eq('business_id', businessId)
        .isFilter('deleted_at', null)
        .gte('txn_date', ymd(from))
        .lte('txn_date', ymd(to))
        .order('txn_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(500);
    return rows.map(CashTx.fromMap).toList();
  }

  /// Transaksi terbaru (untuk beranda).
  Future<List<CashTx>> recent(int limit) async {
    final rows = await _db
        .from('cash_transactions')
        .select(CashTx.columns)
        .eq('business_id', businessId)
        .isFilter('deleted_at', null)
        .order('txn_date', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(CashTx.fromMap).toList();
  }

  /// Aktivitas uang terbaru: kas, pelunasan, pinjaman, dan transaksi hutang.
  Future<List<Activity>> recentActivity(int limit) async {
    final res = await _db.rpc('recent_activity', params: {
      'p_business': businessId,
      'p_limit': limit,
      'p_offset': 0,
    });
    return [
      for (final r in res as List)
        Activity.fromMap(Map<String, dynamic>.from(r as Map))
    ];
  }

  /// Semua transaksi pada rentang (tanpa batas 500), untuk ekspor.
  Future<List<CashTx>> listAll(DateTime from, DateTime to) async {
    const page = 1000;
    final out = <CashTx>[];
    for (var offset = 0;; offset += page) {
      final rows = await _db
          .from('cash_transactions')
          .select(CashTx.columns)
          .eq('business_id', businessId)
          .isFilter('deleted_at', null)
          .gte('txn_date', ymd(from))
          .lte('txn_date', ymd(to))
          .order('txn_date')
          .order('created_at')
          .range(offset, offset + page - 1);
      out.addAll(rows.map(CashTx.fromMap));
      if (rows.length < page) return out;
    }
  }

  /// Rekap per kategori: {category_name, type, total, tx_count}.
  Future<List<Map<String, dynamic>>> byCategory(
      DateTime from, DateTime to) async {
    final res = await _db.rpc('report_by_category', params: {
      'p_business': businessId,
      'p_from': ymd(from),
      'p_to': ymd(to),
    });
    return [for (final r in res as List) Map<String, dynamic>.from(r as Map)];
  }

  Future<Summary> summary(DateTime from, DateTime to) async {
    final res = await _db.rpc('report_summary', params: {
      'p_business': businessId,
      'p_from': ymd(from),
      'p_to': ymd(to),
    });
    return Summary.fromMap(Map<String, dynamic>.from(res as Map));
  }

  /// Rekap per kategori untuk Pembukuan Usaha: totalnya sama dengan Pemasukan dan
  /// Pengeluaran, termasuk irisan Modal barang dan pengeluaran hutang.
  Future<List<Map<String, dynamic>>> plByCategory(
      DateTime from, DateTime to) async {
    final res = await _db.rpc('report_pl_by_category', params: {
      'p_business': businessId,
      'p_from': ymd(from),
      'p_to': ymd(to),
    });
    return [for (final r in res as List) Map<String, dynamic>.from(r as Map)];
  }

  /// Pembukuan Usaha: pemasukan, pengeluaran, dan laba per hari, dipetakan ke
  /// DailyPoint (cashIn = pemasukan, cashOut = pengeluaran, profit = laba).
  Future<List<DailyPoint>> dailyPl(DateTime from, DateTime to) async {
    final res = await _db.rpc('report_daily_pl', params: {
      'p_business': businessId,
      'p_from': ymd(from),
      'p_to': ymd(to),
    });
    return [
      for (final r in res as List)
        DailyPoint(
          parseYmd((r as Map)['day'] as String),
          (r['income'] as num).toInt(),
          (r['expense'] as num).toInt(),
          (r['net'] as num).toInt(),
        )
    ];
  }

  /// Satu titik per hari (hari tanpa transaksi bernilai 0) untuk grafik.
  Future<List<DailyPoint>> daily(DateTime from, DateTime to) async {
    final res = await _db.rpc('report_daily', params: {
      'p_business': businessId,
      'p_from': ymd(from),
      'p_to': ymd(to),
    });
    return [
      for (final r in res as List)
        DailyPoint.fromMap(Map<String, dynamic>.from(r as Map))
    ];
  }

  /// [amount] = uang yang masuk/keluar. Untuk penjualan, isi [sale]; jumlah
  /// harus sudah = Total Penjualan - Diskon + Biaya Tambahan.
  Future<void> add({
    required String type,
    required int amount,
    required DateTime date,
    String? categoryId,
    String? note,
    SaleDetail? sale,
  }) async {
    await _db.from('cash_transactions').insert({
      'business_id': businessId,
      'type': type,
      'amount': amount,
      'category_id': categoryId,
      'note': _clean(note),
      'txn_date': ymd(date),
      'created_by': _uid,
      'is_sale': sale != null,
      'cost_amount': sale?.cost ?? 0,
      'discount_amount': sale?.discount ?? 0,
      'extra_fee': sale?.fee ?? 0,
    });
  }

  Future<void> edit(
    String id, {
    required String type,
    required int amount,
    required DateTime date,
    String? categoryId,
    String? note,
    SaleDetail? sale,
  }) async {
    final rows = await _db
        .from('cash_transactions')
        .update({
          'type': type,
          'amount': amount,
          'category_id': categoryId,
          'note': _clean(note),
          'txn_date': ymd(date),
          'is_sale': sale != null,
          'cost_amount': sale?.cost ?? 0,
          'discount_amount': sale?.discount ?? 0,
          'extra_fee': sale?.fee ?? 0,
        })
        .eq('id', id)
        .select('id');
    _requireAffected(rows);
  }

  Future<void> remove(String id) async {
    final rows = await _db
        .from('cash_transactions')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .select('id');
    _requireAffected(rows);
  }

  /// RLS menolak dengan diam (0 baris) bila pengguna tidak berhak.
  void _requireAffected(List rows) {
    if (rows.isEmpty) {
      throw const PostgrestException(
          message: 'Anda tidak berhak mengubah transaksi ini.');
    }
  }

  String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
