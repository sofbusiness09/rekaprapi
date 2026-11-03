import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/settings/home_prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Akun tiruan: menyimpan satu baris dan mencatat setiap unggahan.
class FakeRemote implements HomePrefsRemote {
  RemotePrefs? stored;
  final saves = <Map<String, dynamic>>[];
  bool failFetch = false;
  bool failSave = false;

  @override
  Future<RemotePrefs?> fetch(String uid) async {
    if (failFetch) throw Exception('offline');
    return stored;
  }

  @override
  Future<void> save(String uid, Map<String, dynamic> prefs, DateTime at) async {
    if (failSave) throw Exception('offline');
    saves.add(prefs);
    stored = RemotePrefs(prefs, at);
  }
}

String _local(HomePrefs p, DateTime? at) => jsonEncode({
      'at': at?.toUtc().toIso8601String(),
      'prefs': p.toJson(),
    });

void main() {
  final t0 = DateTime.utc(2026, 11, 1, 10);
  final t1 = DateTime.utc(2026, 11, 1, 12);
  final t2 = DateTime.utc(2026, 11, 1, 14);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('akun dan perangkat sama-sama kosong: bawaan, tidak ada unggahan',
      () async {
    final remote = FakeRemote();
    final c = HomePrefsController(remote: remote);
    await c.load('u');
    expect(c.value.showBalance, isTrue);
    expect(remote.saves, isEmpty);
  });

  test(
      'akun punya pilihan, perangkat baru: pakai pilihan akun dan salin ke lokal',
      () async {
    final remote = FakeRemote()
      ..stored = RemotePrefs(
          const HomePrefs(showBalance: false, activityCount: 15).toJson(), t1);
    final c = HomePrefsController(remote: remote);
    await c.load('u');
    expect(c.value.showBalance, isFalse);
    expect(c.value.activityCount, 15);

    // Tanpa jaringan, perangkat ini tetap mengingatnya.
    final offline = HomePrefsController();
    await offline.load('u');
    expect(offline.value.showBalance, isFalse);
  });

  test('perubahan dari perangkat lain (lebih baru) mengalahkan salinan lokal',
      () async {
    SharedPreferences.setMockInitialValues({
      'home_prefs_u': _local(const HomePrefs(showProfit: false), t0),
    });
    final remote = FakeRemote()
      ..stored = RemotePrefs(const HomePrefs(showBalance: false).toJson(), t1);
    final c = HomePrefsController(remote: remote);
    await c.load('u');
    expect(c.value.showBalance, isFalse);
    expect(c.value.showProfit, isTrue,
        reason: 'nilai akun yang dipakai, bukan lokal');
    expect(remote.saves, isEmpty);
  });

  test('perubahan di perangkat ini lebih baru: dipakai dan diunggah', () async {
    SharedPreferences.setMockInitialValues({
      'home_prefs_u': _local(const HomePrefs(showProfit: false), t2),
    });
    final remote = FakeRemote()
      ..stored = RemotePrefs(const HomePrefs(showBalance: false).toJson(), t1);
    final c = HomePrefsController(remote: remote);
    await c.load('u');
    expect(c.value.showProfit, isFalse);
    expect(remote.saves, hasLength(1));
    expect(remote.stored!.prefs['showProfit'], isFalse);
  });

  test(
      'pengaturan lama di perangkat ini (tanpa cap waktu) diunggah bila akun kosong',
      () async {
    SharedPreferences.setMockInitialValues({
      'home_prefs_u': jsonEncode(const HomePrefs(showBalance: false).toJson()),
    });
    final remote = FakeRemote();
    final c = HomePrefsController(remote: remote);
    await c.load('u');
    expect(c.value.showBalance, isFalse);
    expect(remote.saves, hasLength(1), reason: 'pengaturan lama tidak hilang');
    expect(remote.stored!.prefs['showBalance'], isFalse);
  });

  test('format lama tanpa cap waktu kalah dari pilihan akun', () async {
    SharedPreferences.setMockInitialValues({
      'home_prefs_u': jsonEncode(const HomePrefs(showBalance: false).toJson()),
    });
    final remote = FakeRemote()
      ..stored = RemotePrefs(const HomePrefs(showFlow: false).toJson(), t1);
    final c = HomePrefsController(remote: remote);
    await c.load('u');
    expect(c.value.showFlow, isFalse);
    expect(c.value.showBalance, isTrue);
    expect(remote.saves, isEmpty);
  });

  test('update menyimpan ke lokal dan ke akun', () async {
    final remote = FakeRemote();
    final c = HomePrefsController(remote: remote);
    await c.load('u');
    await c.update(c.value.copyWith(showBalance: false));
    expect(remote.saves.single['showBalance'], isFalse);

    // Perangkat lain membukanya dan langsung mendapat pilihan yang sama.
    final other = HomePrefsController(remote: remote);
    SharedPreferences.setMockInitialValues({});
    await other.load('u');
    expect(other.value.showBalance, isFalse);
  });

  test('offline saat menyimpan: lokal tetap, diunggah saat berikutnya dibuka',
      () async {
    final remote = FakeRemote()..failSave = true;
    final c = HomePrefsController(remote: remote);
    await c.load('u');
    await c.update(c.value.copyWith(showProfit: false));
    expect(c.value.showProfit, isFalse);
    expect(remote.saves, isEmpty);

    remote.failSave = false; // jaringan pulih; aplikasi dibuka lagi
    final again = HomePrefsController(remote: remote);
    await again.load('u');
    expect(again.value.showProfit, isFalse);
    expect(remote.saves, hasLength(1),
        reason: 'perubahan tertunda ikut terunggah');
  });

  test('offline saat memuat: tetap memakai salinan lokal tanpa galat',
      () async {
    SharedPreferences.setMockInitialValues({
      'home_prefs_u': _local(const HomePrefs(showBalance: false), t1),
    });
    final remote = FakeRemote()..failFetch = true;
    final c = HomePrefsController(remote: remote);
    await c.load('u');
    expect(c.value.showBalance, isFalse);
  });

  test('akun berbeda tidak saling bocor', () async {
    final remote = FakeRemote();
    final c = HomePrefsController(remote: remote);
    await c.load('a');
    await c.update(c.value.copyWith(showBalance: false));

    remote.stored = null; // akun b belum punya pilihan di akun
    await c.load('b');
    expect(c.value.showBalance, isTrue);
  });
}
