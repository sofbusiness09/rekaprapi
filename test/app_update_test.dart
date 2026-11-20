import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rekap_rapi/update/app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _release(String tag,
        {String body = '- Panel bawah baru\n- Perbaikan scan nota'}) =>
    {
      'tag_name': tag,
      'html_url': 'https://github.com/$githubRepo/releases/tag/$tag',
      'body': body,
      'assets': [
        {
          'name': releaseApkName,
          'browser_download_url':
              'https://github.com/$githubRepo/releases/download/$tag/$releaseApkName',
        },
      ],
    };

UpdateChecker _checker(Map<String, dynamic>? latest,
    {String current = '1.0.15',
    DateTime? now,
    int status = 200,
    List<int>? calls}) {
  return UpdateChecker(
    client: MockClient((req) async {
      calls?.add(1);
      expect(req.url.path, '/repos/$githubRepo/releases/latest');
      return http.Response(jsonEncode(latest ?? {}), status);
    }),
    clock: () => now ?? DateTime(2026, 11, 18, 9),
    currentVersion: () async => current,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('membandingkan versi', () {
    expect(compareVersions('1.0.16', '1.0.15'), greaterThan(0));
    expect(compareVersions('1.0.9', '1.0.10'), lessThan(0));
    expect(compareVersions('1.1', '1.0.99'), greaterThan(0));
    expect(compareVersions('1.0.15', '1.0.15+16'), 0);
    expect(compareVersions('2.0', '2.0.0'), 0);
  });

  test('membaca rilis GitHub: versi, catatan, alamat APK, wajib', () {
    final r = AppRelease.fromGithub(_release('v1.0.16',
        body: '- Panel bawah baru\n* [wajib] Perbaikan database\n\n'))!;
    expect(r.version, '1.0.16');
    expect(r.notes, ['Panel bawah baru', 'Perbaikan database']);
    expect(r.mandatory, isTrue);
    expect(r.downloadUrl, endsWith('/download/v1.0.16/RekapRapi.apk'));

    final plain = AppRelease.fromGithub(_release('v1.0.16'))!;
    expect(plain.mandatory, isFalse);

    // Tanpa lampiran APK: halaman rilis.
    final noAsset = AppRelease.fromGithub(
        {'tag_name': 'v2.0.0', 'html_url': 'https://x/rel', 'body': ''})!;
    expect(noAsset.downloadUrl, 'https://x/rel');
    expect(AppRelease.fromGithub({'tag_name': 'nightly'}), isNull);
  });

  test('versi lebih baru ditawarkan; versi sama atau lebih lama tidak',
      () async {
    expect(await _checker(_release('v1.0.16')).check(), isNotNull);
    SharedPreferences.setMockInitialValues({});
    expect(await _checker(_release('v1.0.15')).check(), isNull);
    SharedPreferences.setMockInitialValues({});
    expect(await _checker(_release('v1.0.14')).check(), isNull);
  });

  test('pemeriksaan otomatis paling sering tiap jam', () async {
    final calls = <int>[];
    final t0 = DateTime(2026, 11, 18, 9);
    await _checker(_release('v1.0.16'), now: t0, calls: calls).check();
    await _checker(_release('v1.0.16'),
            now: t0.add(const Duration(minutes: 30)), calls: calls)
        .check();
    expect(calls.length, 1);
    // Dari Pengaturan (force) selalu memeriksa.
    await _checker(_release('v1.0.16'),
            now: t0.add(const Duration(minutes: 30)), calls: calls)
        .check(force: true);
    expect(calls.length, 2);
    await _checker(_release('v1.0.16'),
            now: t0.add(const Duration(minutes: 95)), calls: calls)
        .check();
    expect(calls.length, 3);
  });

  test('Nanti menunda sehari, kecuali pembaruan wajib', () async {
    final t0 = DateTime(2026, 11, 18, 9);
    final c = _checker(_release('v1.0.16'), now: t0);
    final r = await c.check();
    await c.snooze(r!);

    // 7 jam kemudian: lewat jeda pemeriksaan, tetapi masih ditunda.
    final later = t0.add(const Duration(hours: 7));
    expect(await _checker(_release('v1.0.16'), now: later).check(), isNull);
    // Dari Pengaturan tetap ditawarkan.
    expect(await _checker(_release('v1.0.16'), now: later).check(force: true),
        isNotNull);
    // Versi wajib tidak bisa ditunda.
    expect(
        await _checker(_release('v1.0.16', body: '[wajib] x'),
                now: later.add(const Duration(hours: 7)))
            .check(),
        isNotNull);
    // Sehari kemudian muncul lagi.
    expect(
        await _checker(_release('v1.0.16'),
                now: t0.add(const Duration(hours: 25)))
            .check(),
        isNotNull);
  });

  test('galat jaringan: otomatis diam, dari Pengaturan dilaporkan', () async {
    expect(await _checker(null, status: 500).check(), isNull);
    SharedPreferences.setMockInitialValues({});
    expect(() => _checker(null, status: 500).check(force: true),
        throwsA(isA<http.ClientException>()));
    // Belum ada rilis sama sekali.
    SharedPreferences.setMockInitialValues({});
    expect(await _checker(null, status: 404).check(force: true), isNull);
  });

  Future<List<Uri>> showDialogFor(WidgetTester tester, AppRelease r) async {
    final opened = <Uri>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showUpdateDialog(context, r, opener: (u) async {
            opened.add(u);
            return true;
          }),
          child: const Text('buka'),
        ),
      ),
    ));
    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('jendela pembaruan: Perbarui membuka APK, Nanti menutup',
      (tester) async {
    final r = AppRelease.fromGithub(_release('v1.0.16'))!;
    final opened = await showDialogFor(tester, r);
    expect(find.text('Versi 1.0.16 tersedia'), findsOneWidget);
    expect(find.text('• Panel bawah baru'), findsOneWidget);
    await tester.tap(find.text('Perbarui'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), r.downloadUrl);
    expect(find.text('Versi 1.0.16 tersedia'), findsNothing);

    await tester.tap(find.text('buka'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nanti'));
    await tester.pumpAndSettle();
    expect(find.text('Versi 1.0.16 tersedia'), findsNothing);
  });

  testWidgets('pembaruan wajib: tanpa Nanti dan tidak bisa ditutup',
      (tester) async {
    final r = AppRelease.fromGithub(_release('v1.0.16', body: '[wajib] DB'))!;
    final opened = await showDialogFor(tester, r);
    expect(find.text('Nanti'), findsNothing);
    expect(find.textContaining('wajib dipasang'), findsOneWidget);
    // Ketuk di luar jendela: tetap terbuka.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Versi 1.0.16 tersedia'), findsOneWidget);
    // Perbarui membuka unduhan, jendela tetap terbuka.
    await tester.tap(find.text('Perbarui'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(find.text('Versi 1.0.16 tersedia'), findsOneWidget);
  });
}
