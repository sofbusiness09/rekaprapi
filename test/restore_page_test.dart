import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/backup/apps_script_client.dart';
import 'package:rekap_rapi/backup/backup_settings.dart';
import 'package:rekap_rapi/backup/recovery.dart';
import 'package:rekap_rapi/backup/restore_page.dart';
import 'package:rekap_rapi/business/business.dart';

const _url = 'https://script.google.com/macros/s/AKfycbxABC_123-def/exec';
const _token = 'abcdef0123456789abcdef';

RecoveryPayload _payload({String kind = 'business'}) => RecoveryPayload({
      'app': 'RekapRapi',
      'format': 1,
      'createdAt': '2026-11-06T03:00:00Z',
      'business': {'name': 'Toko Lama', 'kind': kind},
      'tables': {
        for (final t in recoveryTables)
          t: {
            'cols': ['id'],
            'rows': <List<Object?>>[],
          },
      },
    });

class _FakeClient extends AppsScriptClient {
  _FakeClient(this.payload);
  final RecoveryPayload payload;

  @override
  Future<RecoveryRead> readRecovery(String url, String token) async =>
      RecoveryRead(payload.toChunks(),
          savedAt: '2026-11-06T03:00:00Z', spreadsheetUrl: 'https://sheet');
}

class _FakeImporter extends RecoveryImporter {
  String? name;
  String? into;
  bool called = false;

  @override
  Future<String> restore(RecoveryPayload payload,
      {required String name,
      String? intoBusinessId,
      void Function(String step, double progress)? onProgress}) async {
    called = true;
    this.name = name;
    into = intoBusinessId;
    return intoBusinessId ?? 'baru-1';
  }
}

class _FakeBackend extends RestoreBackend {
  _FakeBackend({this.names = const [], this.empty = true});

  final List<String> names;
  final bool empty;
  String? connectedId;
  String? connectedUrl;
  String? exceptId;

  @override
  Future<List<String>> conflicts(String scriptUrl, {String? exceptId}) async {
    this.exceptId = exceptId;
    return names;
  }

  @override
  Future<bool> isEmpty(String businessId) async => empty;

  @override
  Future<void> connect(String businessId,
      {required String scriptUrl,
      required String token,
      String? spreadsheetUrl}) async {
    connectedId = businessId;
    connectedUrl = scriptUrl;
  }
}

Future<List<String>> _open(
  WidgetTester tester, {
  required _FakeImporter importer,
  required _FakeBackend backend,
  Business? target,
  BackupSettings? connected,
  String kind = 'business',
}) async {
  final restored = <String>[];
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: RestorePage(
      onRestored: (id) async => restored.add(id),
      target: target,
      connected: connected,
      client: _FakeClient(_payload(kind: kind)),
      importer: importer,
      backend: backend,
    ),
  ));
  if (connected != null) {
    await tester.tap(find.text('Baca dari sheet ini'));
  } else {
    await tester.enterText(find.byType(TextField).at(0), _url);
    await tester.enterText(find.byType(TextField).at(1), _token);
    await tester.tap(find.text('Baca data'));
  }
  await tester.pumpAndSettle();
  return restored;
}

Future<void> _confirmRestore(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Pulihkan'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pulihkan').last);
  await tester.pumpAndSettle();
}

const _owner = Business(id: 'b9', name: 'Toko Kosong', role: 'owner');

void main() {
  testWidgets('pembukuan baru: backup dilanjutkan ke sheet sumber',
      (tester) async {
    final importer = _FakeImporter();
    final backend = _FakeBackend();
    final restored = await _open(tester, importer: importer, backend: backend);

    // Tanpa pembukuan target tidak ada pilihan tujuan.
    expect(find.text('Pembukuan ini'), findsNothing);
    expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, true);

    await _confirmRestore(tester);
    expect(importer.name, 'Toko Lama (pulihan)');
    expect(importer.into, isNull);
    expect(backend.connectedId, 'baru-1');
    expect(backend.connectedUrl, _url);
    expect(restored, ['baru-1']);
  });

  testWidgets('saklar dimatikan: backup tidak disambungkan', (tester) async {
    final importer = _FakeImporter();
    final backend = _FakeBackend();
    await _open(tester, importer: importer, backend: backend);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await _confirmRestore(tester);
    expect(importer.called, isTrue);
    expect(backend.connectedId, isNull);
  });

  testWidgets('sheet masih dipakai pembukuan lain: mati dan diperingatkan',
      (tester) async {
    final importer = _FakeImporter();
    final backend = _FakeBackend(names: ['Toko Rahmart']);
    await _open(tester, importer: importer, backend: backend);

    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false);
    expect(
        find.textContaining(
            'masih dipakai untuk backup pembukuan "Toko Rahmart"'),
        findsOneWidget);

    // Menghidupkan butuh konfirmasi; Batal membiarkannya mati.
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Tetap sambungkan?'), findsOneWidget);
    await tester.tap(find.text('Batal'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        false);

    await _confirmRestore(tester);
    expect(backend.connectedId, isNull);
  });

  testWidgets('peringatan disetujui: tetap disambungkan', (tester) async {
    final importer = _FakeImporter();
    final backend = _FakeBackend(names: ['Toko Rahmart']);
    await _open(tester, importer: importer, backend: backend);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tetap sambungkan'));
    await tester.pumpAndSettle();
    await _confirmRestore(tester);
    expect(backend.connectedId, 'baru-1');
  });

  testWidgets('pembukuan kosong milik sendiri bisa menjadi tujuan',
      (tester) async {
    final importer = _FakeImporter();
    final backend = _FakeBackend();
    final restored = await _open(tester,
        importer: importer, backend: backend, target: _owner);
    expect(backend.exceptId, 'b9');

    await tester.tap(find.text('Pembukuan ini'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Data dimasukkan ke "Toko Kosong"'),
        findsOneWidget);
    expect(find.text('Nama pembukuan baru'), findsNothing);

    await _confirmRestore(tester);
    expect(importer.into, 'b9');
    expect(importer.name, 'Toko Kosong');
    expect(backend.connectedId, 'b9');
    expect(restored, ['b9']);
  });

  testWidgets('tujuan sudah tersambung ke sheet sumber: tidak disambung ulang',
      (tester) async {
    final importer = _FakeImporter();
    final backend = _FakeBackend();
    await _open(tester,
        importer: importer,
        backend: backend,
        target: _owner,
        connected: const BackupSettings(scriptUrl: _url, token: _token));
    await tester.tap(find.text('Pembukuan ini'));
    await tester.pumpAndSettle();
    expect(find.byType(SwitchListTile), findsNothing);
    await _confirmRestore(tester);
    expect(importer.into, 'b9');
    expect(backend.connectedId, isNull);
  });

  testWidgets('pilihan "Pembukuan ini" tidak muncul bila tidak memenuhi syarat',
      (tester) async {
    // Sudah berisi data.
    await _open(tester,
        importer: _FakeImporter(),
        backend: _FakeBackend(empty: false),
        target: _owner);
    expect(find.text('Pembukuan ini'), findsNothing);

    // Bukan Pemilik.
    await _open(tester,
        importer: _FakeImporter(),
        backend: _FakeBackend(),
        target: const Business(id: 'b9', name: 'T', role: 'admin'));
    expect(find.text('Pembukuan ini'), findsNothing);

    // Jenis berbeda dengan backup.
    await _open(tester,
        importer: _FakeImporter(),
        backend: _FakeBackend(),
        target: _owner,
        kind: 'personal');
    expect(find.text('Pembukuan ini'), findsNothing);
  });
}
