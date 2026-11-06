import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cash/cash_models.dart';

/// Bagian Beranda yang bisa digeser urutannya. Kartu saldo dan arus kas bulan
/// ini dihitung satu bagian (`hero`).
const homeSections = ['hero', 'profit', 'quick', 'debt', 'activity'];

const homeSectionTitles = {
  'hero': 'Saldo dan kas bulan ini',
  'profit': 'Keuntungan bulan ini',
  'quick': 'Tombol cepat',
  'debt': 'Piutang dan utang belum lunas',
  'activity': 'Aktivitas terbaru',
};

/// Pilihan tampilan satu usaha: apa yang tampil di Beranda dan di tab Transaksi.
/// Tiap usaha punya pilihan sendiri. Bawaan Beranda = semuanya tampil; bawaan
/// Transaksi = hanya pemasukan dan pengeluaran, tanpa catatan utang piutang.
@immutable
class HomePrefs {
  const HomePrefs({
    this.showBalance = true,
    this.showFlow = true,
    this.showProfit = true,
    this.showQuickActions = true,
    this.showDebtCards = true,
    this.showActivity = true,
    this.actCashIn = true,
    this.actCashOut = true,
    this.actCredit = true,
    this.actPayments = true,
    this.actLoans = true,
    this.activityCount = 8,
    this.order = homeSections,
    this.txIn = true,
    this.txOut = true,
    this.txCredit = false,
    this.txDebtCash = false,
    this.showCashBalance = false,
  });

  /// Saldo kas (angka besar).
  final bool showBalance;

  /// Kas masuk dan keluar bulan ini.
  final bool showFlow;

  /// Keuntungan penjualan bulan ini.
  final bool showProfit;

  /// Tombol Kas masuk / Kas keluar / Utang.
  final bool showQuickActions;

  /// Piutang dan utang yang belum lunas.
  final bool showDebtCards;

  /// Daftar aktivitas terbaru.
  final bool showActivity;

  // Jenis aktivitas yang boleh tampil di Aktivitas terbaru.
  final bool actCashIn;
  final bool actCashOut;
  final bool actCredit;
  final bool actPayments;
  final bool actLoans;

  /// Jumlah aktivitas yang ditampilkan.
  final int activityCount;

  /// Urutan bagian Beranda dari atas ke bawah (selalu memuat semua id di [homeSections]).
  final List<String> order;

  // Isi tab Transaksi.
  final bool txIn;
  final bool txOut;

  /// Transaksi hutang: penjualan atau pembelian kredit yang belum dibayar.
  final bool txCredit;

  /// Kas otomatis dari utang piutang: pemberian, pelunasan, penerimaan, pembayaran.
  final bool txDebtCash;

  /// Pembukuan Usaha: tampilkan Saldo Kas (uang di tangan). Bawaannya disembunyikan;
  /// yang utama adalah Pemasukan, Pengeluaran, dan Laba.
  final bool showCashBalance;

  static const countOptions = [5, 8, 10, 15];

  bool get showHero => showBalance || showFlow;

  bool sectionShown(String id) {
    switch (id) {
      case 'hero':
        return showHero;
      case 'profit':
        return showProfit;
      case 'quick':
        return showQuickActions;
      case 'debt':
        return showDebtCards;
      case 'activity':
        return showActivity;
    }
    return false;
  }

  bool get anySection => homeSections.any(sectionShown);

  bool get anyActivityType =>
      actCashIn || actCashOut || actCredit || actPayments || actLoans;

  /// Apakah aktivitas ini boleh tampil menurut jenisnya.
  bool allows(Activity a) {
    switch (a.type) {
      case ActivityType.cashIn:
        return actCashIn;
      case ActivityType.cashOut:
        return actCashOut;
      case ActivityType.credit:
        return actCredit;
      case ActivityType.payment:
        return actPayments;
      case ActivityType.loan:
        return actLoans;
    }
  }

  HomePrefs copyWith({
    bool? showBalance,
    bool? showFlow,
    bool? showProfit,
    bool? showQuickActions,
    bool? showDebtCards,
    bool? showActivity,
    bool? actCashIn,
    bool? actCashOut,
    bool? actCredit,
    bool? actPayments,
    bool? actLoans,
    int? activityCount,
    List<String>? order,
    bool? txIn,
    bool? txOut,
    bool? txCredit,
    bool? txDebtCash,
    bool? showCashBalance,
  }) =>
      HomePrefs(
        showBalance: showBalance ?? this.showBalance,
        showFlow: showFlow ?? this.showFlow,
        showProfit: showProfit ?? this.showProfit,
        showQuickActions: showQuickActions ?? this.showQuickActions,
        showDebtCards: showDebtCards ?? this.showDebtCards,
        showActivity: showActivity ?? this.showActivity,
        actCashIn: actCashIn ?? this.actCashIn,
        actCashOut: actCashOut ?? this.actCashOut,
        actCredit: actCredit ?? this.actCredit,
        actPayments: actPayments ?? this.actPayments,
        actLoans: actLoans ?? this.actLoans,
        activityCount: activityCount ?? this.activityCount,
        order: order ?? this.order,
        txIn: txIn ?? this.txIn,
        txOut: txOut ?? this.txOut,
        txCredit: txCredit ?? this.txCredit,
        txDebtCash: txDebtCash ?? this.txDebtCash,
        showCashBalance: showCashBalance ?? this.showCashBalance,
      );

  Map<String, dynamic> toJson() => {
        'showBalance': showBalance,
        'showFlow': showFlow,
        'showProfit': showProfit,
        'showQuickActions': showQuickActions,
        'showDebtCards': showDebtCards,
        'showActivity': showActivity,
        'actCashIn': actCashIn,
        'actCashOut': actCashOut,
        'actCredit': actCredit,
        'actPayments': actPayments,
        'actLoans': actLoans,
        'activityCount': activityCount,
        'order': order,
        'txIn': txIn,
        'txOut': txOut,
        'txCredit': txCredit,
        'txDebtCash': txDebtCash,
        'showCashBalance': showCashBalance,
      };

  /// Nilai yang hilang atau tidak dikenal memakai bawaan.
  factory HomePrefs.fromJson(Map<String, dynamic> j) {
    bool b(String k, [bool fallback = true]) {
      final v = j[k];
      return v is bool ? v : fallback;
    }

    final count = j['activityCount'];
    return HomePrefs(
      showBalance: b('showBalance'),
      showFlow: b('showFlow'),
      showProfit: b('showProfit'),
      showQuickActions: b('showQuickActions'),
      showDebtCards: b('showDebtCards'),
      showActivity: b('showActivity'),
      actCashIn: b('actCashIn'),
      actCashOut: b('actCashOut'),
      actCredit: b('actCredit'),
      actPayments: b('actPayments'),
      actLoans: b('actLoans'),
      activityCount: count is int && countOptions.contains(count) ? count : 8,
      order: normalizeOrder(j['order']),
      txIn: b('txIn'),
      txOut: b('txOut'),
      txCredit: b('txCredit', false),
      txDebtCash: b('txDebtCash', false),
      showCashBalance: b('showCashBalance', false),
    );
  }

  /// Urutan yang dikenal dipertahankan, id ganda dan asing dibuang, dan bagian
  /// yang belum ada ditaruh di akhir.
  static List<String> normalizeOrder(Object? raw) {
    final seen = <String>[];
    if (raw is List) {
      for (final id in raw) {
        if (id is String && homeSections.contains(id) && !seen.contains(id)) {
          seen.add(id);
        }
      }
    }
    for (final id in homeSections) {
      if (!seen.contains(id)) seen.add(id);
    }
    return List.unmodifiable(seen);
  }
}

/// Salinan pilihan yang tersimpan di akun (database).
class RemotePrefs {
  const RemotePrefs(this.prefs, this.updatedAt);

  final Map<String, dynamic> prefs;
  final DateTime updatedAt;
}

/// Penyimpanan pilihan di akun. Dipisah agar logika sinkron bisa diuji tanpa jaringan.
/// [businessId] null = pilihan lama per akun (sebelum tiap usaha punya pilihan sendiri).
abstract class HomePrefsRemote {
  /// null bila akun belum punya pilihan tersimpan.
  Future<RemotePrefs?> fetch(String uid, String? businessId);

  Future<void> save(
      String uid, String? businessId, Map<String, dynamic> prefs, DateTime at);
}

/// Menyimpan di tabel `user_business_settings` (satu baris per pengguna dan usaha;
/// hanya pemiliknya yang bisa membaca dan menulis).
class SupabaseHomePrefsRemote implements HomePrefsRemote {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<RemotePrefs?> fetch(String uid, String? businessId) async {
    final Map<String, dynamic>? row;
    if (businessId == null) {
      row = await _db
          .from('user_settings')
          .select('home_prefs, updated_at')
          .eq('user_id', uid)
          .maybeSingle();
    } else {
      row = await _db
          .from('user_business_settings')
          .select('home_prefs, updated_at')
          .eq('user_id', uid)
          .eq('business_id', businessId)
          .maybeSingle();
    }
    if (row == null) return null;
    final prefs = Map<String, dynamic>.from(row['home_prefs'] as Map);
    if (prefs.isEmpty) return null;
    return RemotePrefs(prefs, DateTime.parse(row['updated_at'] as String));
  }

  @override
  Future<void> save(String uid, String? businessId, Map<String, dynamic> prefs,
      DateTime at) async {
    final stamp = at.toUtc().toIso8601String();
    if (businessId == null) {
      await _db.from('user_settings').upsert({
        'user_id': uid,
        'home_prefs': prefs,
        'updated_at': stamp,
      }, onConflict: 'user_id');
    } else {
      await _db.from('user_business_settings').upsert({
        'user_id': uid,
        'business_id': businessId,
        'home_prefs': prefs,
        'updated_at': stamp,
      }, onConflict: 'user_id,business_id');
    }
  }
}

/// Memuat dan menyimpan pilihan tampilan untuk pengguna dan usaha yang sedang dibuka.
///
/// Pilihan tersimpan di akun sehingga ikut ke semua perangkat, dan disalin di
/// perangkat ini agar Beranda langsung tampil (dan tetap bekerja saat offline).
/// Bila salinan lokal dan akun berbeda, yang terakhir diubah yang dipakai.
class HomePrefsController extends ChangeNotifier {
  HomePrefsController({HomePrefsRemote? remote}) : _remote = remote;

  final HomePrefsRemote? _remote;

  HomePrefs _value = const HomePrefs();
  HomePrefs get value => _value;

  String? _uid;
  String? _businessId;
  DateTime? _at; // waktu perubahan terakhir pilihan yang sedang dipakai

  String get _key => _businessId == null
      ? 'home_prefs_$_uid'
      : 'home_prefs_${_uid}_$_businessId';

  /// Pilihan di perangkat ini; [at] null untuk format lama yang belum bercap waktu.
  Future<(HomePrefs, DateTime?)?> _readLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['prefs'] is Map) {
        final at =
            j['at'] is String ? DateTime.tryParse(j['at'] as String) : null;
        return (
          HomePrefs.fromJson(Map<String, dynamic>.from(j['prefs'] as Map)),
          at
        );
      }
      return (HomePrefs.fromJson(j), null); // format lama: pilihan saja
    } catch (_) {
      return null; // data rusak atau penyimpanan tidak tersedia
    }
  }

  Future<void> _writeLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _key,
          jsonEncode({
            'at': _at?.toUtc().toIso8601String(),
            'prefs': _value.toJson(),
          }));
    } catch (_) {
      // Tetap berlaku selama aplikasi terbuka walau gagal disalin.
    }
  }

  Future<void> _push() async {
    final remote = _remote;
    final uid = _uid;
    if (remote == null || uid == null) return;
    try {
      await remote.save(
          uid, _businessId, _value.toJson(), _at ?? DateTime.now());
    } catch (_) {
      // Gagal (mis. offline): salinan lokal lebih baru dan akan diunggah saat berikutnya dibuka.
    }
  }

  Future<void> load(String uid, {String? businessId}) async {
    if (_uid != uid || _businessId != businessId) {
      _value =
          const HomePrefs(); // jangan menampilkan pilihan akun atau usaha sebelumnya
      _at = null;
    }
    _uid = uid;
    _businessId = businessId;

    final local = await _readLocal();
    if (_uid != uid || _businessId != businessId)
      return; // sudah berpindah lagi
    if (local != null) {
      _value = local.$1;
      _at = local.$2;
    }
    notifyListeners(); // tampil segera dari salinan lokal

    final remote = _remote;
    if (remote == null) return;
    try {
      final r = await remote.fetch(uid, businessId);
      if (_uid != uid || _businessId != businessId) return;
      if (r == null) {
        // Akun belum punya pilihan: unggah milik perangkat ini bila ada.
        if (local != null) {
          _at ??= DateTime.now();
          await _writeLocal();
          await _push();
        }
        return;
      }
      final localAt = local?.$2;
      if (local != null && localAt != null && localAt.isAfter(r.updatedAt)) {
        await _push(); // perubahan di perangkat ini lebih baru
        return;
      }
      _value = HomePrefs.fromJson(r.prefs);
      _at = r.updatedAt;
      await _writeLocal();
      notifyListeners();
    } catch (_) {
      // Offline atau gagal: tetap memakai salinan lokal.
    }
  }

  Future<void> update(HomePrefs next) async {
    _value = next;
    _at = DateTime.now();
    notifyListeners();
    if (_uid == null) return;
    await _writeLocal();
    await _push();
  }

  Future<void> reset() => update(const HomePrefs());
}

/// Satu pengatur pilihan tampilan untuk seluruh aplikasi (usaha aktif).
final homePrefs = HomePrefsController(remote: SupabaseHomePrefsRemote());
