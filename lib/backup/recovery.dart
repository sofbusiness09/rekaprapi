import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business.dart';
import '../common/format.dart';
import 'apps_script_client.dart';

/// Tabel yang ikut data pemulihan, dalam urutan memasukkannya (induk dulu).
const recoveryTables = ['categories', 'contacts', 'debts', 'payments', 'cash'];

/// Kolom tiap tabel yang disimpan. Nama kolom sama dengan yang dibaca fungsi
/// `restore_rows` di database.
const _columns = <String, List<String>>{
  'categories': ['id', 'name', 'type', 'is_system', 'is_sale'],
  'contacts': ['id', 'name', 'phone', 'address', 'note', 'created_at'],
  'debts': [
    'id',
    'contact_id',
    'kind',
    'amount',
    'cash_moved',
    'debt_date',
    'due_date',
    'note',
    'created_at',
    'is_sale',
    'cost_amount',
    'discount_amount',
    'extra_fee',
  ],
  'payments': [
    'id',
    'debt_id',
    'amount',
    'paid_on',
    'note',
    'created_at',
    'method',
    'offset_group',
  ],
  'cash': [
    'id',
    'type',
    'amount',
    'category_id',
    'note',
    'txn_date',
    'created_at',
    'debt_id',
    'debt_payment_id',
    'is_sale',
    'cost_amount',
    'discount_amount',
    'extra_fee',
  ],
};

/// Satu potongan teks di Google Sheet dibatasi sekitar 50.000 karakter.
const recoveryChunkSize = 30000;

/// Data lengkap satu pembukuan dalam bentuk mesin, untuk dikirim ke Google Sheet saat
/// backup dan dibaca kembali saat pemulihan. Tabel disimpan sebagai daftar kolom dan
/// baris berupa larik agar ukurannya kecil.
class RecoveryPayload {
  RecoveryPayload(this.data);

  static const format = 1;

  final Map<String, dynamic> data;

  /// Nama pembukuan asal.
  String get name => (data['business'] as Map)['name'] as String;

  BusinessKind get kind =>
      BusinessKind.parse((data['business'] as Map)['kind'] as String?);

  String? get address => (data['business'] as Map)['address'] as String?;
  String? get phone => (data['business'] as Map)['phone'] as String?;

  DateTime? get createdAt => data['createdAt'] == null
      ? null
      : DateTime.tryParse(data['createdAt'] as String)?.toLocal();

  Map<String, dynamic> _table(String name) =>
      (data['tables'] as Map)[name] as Map<String, dynamic>;

  /// Jumlah baris per tabel.
  int count(String table) => (_table(table)['rows'] as List).length;

  /// Baris tabel sebagai daftar objek (kolom -> nilai), siap dikirim ke database.
  List<Map<String, dynamic>> rows(String table) {
    final t = _table(table);
    final cols = [for (final c in t['cols'] as List) c as String];
    return [
      for (final r in t['rows'] as List)
        {for (var i = 0; i < cols.length; i++) cols[i]: (r as List)[i]},
    ];
  }

  /// Teks JSON dipotong menjadi bagian-bagian yang muat di satu sel Google Sheet.
  List<String> toChunks([int size = recoveryChunkSize]) {
    final text = jsonEncode(data);
    return [
      for (var i = 0; i < text.length; i += size)
        text.substring(i, i + size > text.length ? text.length : i + size),
    ];
  }

  /// Menyusun kembali dari potongan yang dibaca; melempar [BackupException] bila isinya
  /// tidak dikenali (rusak, terpotong, atau dari versi aplikasi yang lebih baru).
  static RecoveryPayload fromChunks(List<String> chunks) {
    try {
      final decoded = jsonDecode(chunks.join());
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      return validated(decoded);
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException(
          'Data pemulihan di Google Sheet rusak atau tidak lengkap. Jalankan Backup lagi dari aplikasi, lalu coba pulihkan.');
    }
  }

  static RecoveryPayload validated(Map<String, dynamic> d) {
    if (d['app'] != 'RekapRapi') throw const FormatException('bukan RekapRapi');
    final f = d['format'];
    if (f is! int || f > format) {
      throw const BackupException(
          'Data pemulihan dibuat oleh versi RekapRapi yang lebih baru. Perbarui aplikasi lebih dulu.');
    }
    final b = d['business'];
    if (b is! Map || (b['name'] as String?)?.trim().isEmpty != false) {
      throw const FormatException('nama kosong');
    }
    final tables = d['tables'];
    if (tables is! Map) throw const FormatException('tabel');
    for (final t in recoveryTables) {
      final table = tables[t];
      if (table is! Map || table['cols'] is! List || table['rows'] is! List) {
        throw FormatException('tabel $t');
      }
      final cols = (table['cols'] as List).length;
      for (final r in table['rows'] as List) {
        if (r is! List || r.length != cols) throw FormatException('baris $t');
      }
    }
    return RecoveryPayload(d);
  }

  /// Ringkasan untuk ditampilkan sebelum memulihkan.
  String get summary =>
      '${count('cash')} transaksi, ${count('debts')} catatan utang piutang, '
      '${count('contacts')} kontak, ${count('categories')} kategori';
}

/// Mengambil seluruh data satu pembukuan (semua waktu) dan menyusunnya menjadi
/// [RecoveryPayload].
class RecoveryExporter {
  RecoveryExporter(this.business);

  final Business business;
  SupabaseClient get _db => Supabase.instance.client;

  Future<List<List<Object?>>> _all(
      String table, List<String> cols, bool softDeleted) async {
    const page = 1000;
    final out = <List<Object?>>[];
    for (var from = 0;; from += page) {
      var q = _db
          .from(table)
          .select(cols.join(', '))
          .eq('business_id', business.id);
      if (softDeleted) q = q.isFilter('deleted_at', null);
      final rows = await q.order('id').range(from, from + page - 1);
      for (final r in rows) {
        out.add([for (final c in cols) r[c]]);
      }
      if (rows.length < page) return out;
    }
  }

  Future<RecoveryPayload> export({DateTime? now}) async {
    final results = await Future.wait([
      _all('categories', _columns['categories']!, false),
      _all('contacts', _columns['contacts']!, true),
      _all('debts', _columns['debts']!, true),
      _all('debt_payments', _columns['payments']!, true),
      _all('cash_transactions', _columns['cash']!, true),
    ]);
    final meta = await _db
        .from('businesses')
        .select('address, phone')
        .eq('id', business.id)
        .maybeSingle();
    return RecoveryPayload({
      'app': 'RekapRapi',
      'format': RecoveryPayload.format,
      'createdAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'business': {
        'name': business.name,
        'kind': business.kind.apiValue,
        'address': meta?['address'],
        'phone': meta?['phone'],
      },
      'tables': {
        for (var i = 0; i < recoveryTables.length; i++)
          recoveryTables[i]: {
            'cols': _columns[recoveryTables[i]],
            'rows': results[i],
          },
      },
    });
  }
}

/// Memasukkan [RecoveryPayload] sebagai pembukuan baru lewat fungsi database
/// restore_begin, restore_rows, dan restore_finish.
class RecoveryImporter {
  RecoveryImporter({this.batchSize = 500});

  /// Baris per panggilan (database menerima paling banyak 2.000).
  final int batchSize;
  SupabaseClient get _db => Supabase.instance.client;

  /// Mengembalikan id pembukuan hasil pemulihan.
  ///
  /// Tanpa [intoBusinessId]: dibuat pembukuan baru bernama [name]; bila gagal di
  /// tengah, pembukuan setengah jadi dihapus.
  /// Dengan [intoBusinessId]: data dimasukkan ke pembukuan itu, yang harus masih
  /// kosong (dijaga database); bila gagal, pembukuan dikembalikan kosong dan tidak
  /// dihapus. Kategori buatan pengguna di pembukuan itu dipertahankan.
  Future<String> restore(
    RecoveryPayload payload, {
    required String name,
    String? intoBusinessId,
    void Function(String step, double progress)? onProgress,
  }) async {
    final into = intoBusinessId != null;
    // Kategori yang sudah dibuat di pembukuan tujuan, untuk ditambahkan kembali.
    final kept = intoBusinessId != null
        ? await _customCategories(intoBusinessId)
        : const <(String, String)>[];

    final String id;
    if (into) {
      id = await _db.rpc('restore_into_begin', params: {
        'p_business': intoBusinessId,
        'p_kind': payload.kind.apiValue,
      }) as String;
    } else {
      id = await _db.rpc('restore_begin', params: {
        'p_name': name,
        'p_kind': payload.kind.apiValue,
        'p_address': payload.address,
        'p_phone': payload.phone,
      }) as String;
    }
    try {
      final total = recoveryTables.fold<int>(0, (s, t) => s + payload.count(t));
      var done = 0;
      for (final table in recoveryTables) {
        final rows = payload.rows(table);
        for (var i = 0; i < rows.length; i += batchSize) {
          final end = i + batchSize > rows.length ? rows.length : i + batchSize;
          onProgress?.call(
              'Memulihkan ${_label(table)}…', total == 0 ? 1 : done / total);
          await _db.rpc('restore_rows', params: {
            'p_business': id,
            'p_table': table,
            'p_rows': rows.sublist(i, end),
          });
          done += end - i;
        }
      }
      onProgress?.call('Merapikan…', 1);
      await _db.rpc('restore_finish', params: {'p_business': id});
    } catch (_) {
      try {
        await _db.rpc(into ? 'restore_abort' : 'delete_business',
            params: {'p_business': id});
      } catch (_) {
        // Pembukuan setengah jadi bisa dihapus sendiri dari Pengaturan.
      }
      rethrow;
    }
    await _addMissingCategories(id, kept);
    return id;
  }

  Future<List<(String, String)>> _customCategories(String businessId) async {
    try {
      final rows = await _db
          .from('categories')
          .select('name, type')
          .eq('business_id', businessId)
          .eq('is_system', false);
      return [for (final r in rows) (r['name'] as String, r['type'] as String)];
    } catch (_) {
      return const [];
    }
  }

  /// Menambahkan kembali kategori yang tidak ada di backup. Gagal di sini tidak
  /// membatalkan pemulihan yang sudah berhasil.
  Future<void> _addMissingCategories(
      String businessId, List<(String, String)> kept) async {
    if (kept.isEmpty) return;
    try {
      final rows = await _db
          .from('categories')
          .select('name, type')
          .eq('business_id', businessId);
      final have = {for (final r in rows) '${r['type']}:${r['name']}'};
      final missing = [
        for (final k in kept)
          if (!have.contains('${k.$2}:${k.$1}'))
            {'business_id': businessId, 'name': k.$1, 'type': k.$2},
      ];
      if (missing.isNotEmpty) await _db.from('categories').insert(missing);
    } catch (_) {
      // Kategori bisa ditambahkan lagi dari Pengaturan.
    }
  }

  static String _label(String table) => switch (table) {
        'categories' => 'kategori',
        'contacts' => 'kontak',
        'debts' => 'utang piutang',
        'payments' => 'pembayaran',
        _ => 'transaksi',
      };
}

/// Memformat waktu backup untuk pesan ke pengguna.
String savedAtLabel(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  return t == null ? '-' : timeId(t);
}
