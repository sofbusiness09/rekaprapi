import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../cash/cash_models.dart';

/// Pilihan apa yang tampil di Beranda. Bawaan = semuanya tampil (sama seperti
/// tampilan awal), jadi pengguna yang tidak mengubah apa pun tidak melihat perbedaan.
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

  static const countOptions = [5, 8, 10, 15];

  bool get showHero => showBalance || showFlow;

  bool get anySection =>
      showHero ||
      showProfit ||
      showQuickActions ||
      showDebtCards ||
      showActivity;

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
      };

  /// Nilai yang hilang atau tidak dikenal memakai bawaan.
  factory HomePrefs.fromJson(Map<String, dynamic> j) {
    bool b(String k) {
      final v = j[k];
      return v is bool ? v : true;
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
    );
  }
}

/// Salinan pilihan Beranda yang tersimpan di akun (database).
class RemotePrefs {
  const RemotePrefs(this.prefs, this.updatedAt);

  final Map<String, dynamic> prefs;
  final DateTime updatedAt;
}

/// Penyimpanan pilihan di akun. Dipisah agar logika sinkron bisa diuji tanpa jaringan.
abstract class HomePrefsRemote {
  /// null bila akun belum punya pilihan tersimpan.
  Future<RemotePrefs?> fetch(String uid);

  Future<void> save(String uid, Map<String, dynamic> prefs, DateTime at);
}

/// Menyimpan di tabel `user_settings` (hanya pemiliknya yang bisa membaca/menulis).
class SupabaseHomePrefsRemote implements HomePrefsRemote {
  SupabaseClient get _db => Supabase.instance.client;

  @override
  Future<RemotePrefs?> fetch(String uid) async {
    final row = await _db
        .from('user_settings')
        .select('home_prefs, updated_at')
        .eq('user_id', uid)
        .maybeSingle();
    if (row == null) return null;
    final prefs = Map<String, dynamic>.from(row['home_prefs'] as Map);
    if (prefs.isEmpty) return null;
    return RemotePrefs(prefs, DateTime.parse(row['updated_at'] as String));
  }

  @override
  Future<void> save(String uid, Map<String, dynamic> prefs, DateTime at) async {
    await _db.from('user_settings').upsert({
      'user_id': uid,
      'home_prefs': prefs,
      'updated_at': at.toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }
}

/// Memuat dan menyimpan pilihan Beranda untuk pengguna yang sedang masuk.
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
  DateTime? _at; // waktu perubahan terakhir pilihan yang sedang dipakai

  String get _key => 'home_prefs_$_uid';

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
      await remote.save(uid, _value.toJson(), _at ?? DateTime.now());
    } catch (_) {
      // Gagal (mis. offline): salinan lokal lebih baru dan akan diunggah saat berikutnya dibuka.
    }
  }

  Future<void> load(String uid) async {
    if (_uid != uid) {
      _value = const HomePrefs(); // jangan menampilkan pilihan akun sebelumnya
      _at = null;
    }
    _uid = uid;

    final local = await _readLocal();
    if (local != null) {
      _value = local.$1;
      _at = local.$2;
    }
    notifyListeners(); // tampil segera dari salinan lokal

    final remote = _remote;
    if (remote == null) return;
    try {
      final r = await remote.fetch(uid);
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

/// Satu pengatur pilihan Beranda untuk seluruh aplikasi.
final homePrefs = HomePrefsController(remote: SupabaseHomePrefsRemote());
