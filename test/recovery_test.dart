import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rekap_rapi/backup/apps_script_client.dart';
import 'package:rekap_rapi/backup/recovery.dart';

const _url = 'https://script.google.com/macros/s/AKfycbxABC_123-def/exec';

Map<String, dynamic> _data({int format = 1, String name = 'Warung'}) => {
      'app': 'RekapRapi',
      'format': format,
      'createdAt': '2026-11-06T03:00:00Z',
      'business': {
        'name': name,
        'kind': 'business',
        'address': 'Jl. Mawar',
        'phone': '0812'
      },
      'tables': {
        'categories': {
          'cols': ['id', 'name'],
          'rows': [
            ['c1', 'Penjualan'],
          ],
        },
        'contacts': {
          'cols': ['id', 'name'],
          'rows': [
            ['k1', 'Bu Ani'],
            ['k2', 'Pak Budi'],
          ],
        },
        'debts': {
          'cols': ['id'],
          'rows': <List<Object?>>[]
        },
        'payments': {
          'cols': ['id'],
          'rows': <List<Object?>>[]
        },
        'cash': {
          'cols': ['id', 'amount'],
          'rows': [
            ['t1', 95000],
          ],
        },
      },
    };

void main() {
  group('RecoveryPayload', () {
    test('potongan disusun kembali menjadi data yang sama', () {
      final p = RecoveryPayload(_data());
      final chunks = p.toChunks(40);
      expect(chunks.length, greaterThan(3));
      expect(chunks.every((c) => c.length <= 40), isTrue);
      final back = RecoveryPayload.fromChunks(chunks);
      expect(back.name, 'Warung');
      expect(back.address, 'Jl. Mawar');
      expect(back.count('contacts'), 2);
      expect(back.rows('cash').single, {'id': 't1', 'amount': 95000});
      expect(back.summary, contains('1 transaksi'));
    });

    test('data rusak atau terpotong ditolak dengan pesan', () {
      final chunks = RecoveryPayload(_data()).toChunks(40);
      expect(() => RecoveryPayload.fromChunks(chunks.take(2).toList()),
          throwsA(isA<BackupException>()));
      expect(() => RecoveryPayload.fromChunks(['[1,2]']),
          throwsA(isA<BackupException>()));
    });

    test('format dari versi aplikasi yang lebih baru ditolak', () {
      final chunks = RecoveryPayload(_data(format: 9)).toChunks();
      expect(
        () => RecoveryPayload.fromChunks(chunks),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'pesan', contains('lebih baru'))),
      );
    });

    test('baris yang jumlah kolomnya tidak cocok ditolak', () {
      final d = _data();
      ((d['tables'] as Map)['cash'] as Map)['rows'] = [
        ['t1']
      ];
      expect(() => RecoveryPayload.fromChunks(RecoveryPayload(d).toChunks()),
          throwsA(isA<BackupException>()));
    });
  });

  group('AppsScriptClient pemulihan', () {
    test('skrip lama tanpa potongan meminta pembaruan', () async {
      final client =
          MockClient((_) async => http.Response(jsonEncode({'ok': true}), 200));
      expect(
        AppsScriptClient(client: client).readRecovery(_url, 'tok'),
        throwsA(
            isA<BackupException>().having((e) => e.code, 'kode', 'old_script')),
      );
    });

    test('membaca potongan dan waktu simpan', () async {
      final client = MockClient((req) async {
        expect(jsonDecode(req.body)['read'], true);
        return http.Response(
            jsonEncode({
              'ok': true,
              'chunks': ['ab', 'cd'],
              'savedAt': '2026-11-06T03:00:00Z',
            }),
            200);
      });
      final r =
          await AppsScriptClient(client: client).readRecovery(_url, 'tok');
      expect(r.chunks.join(), 'abcd');
      expect(r.savedAt, isNotNull);
    });

    test('versi skrip menentukan apakah sudah terbaru', () {
      expect(const ScriptInfo().current, isFalse);
      expect(const ScriptInfo(version: 1).current, isFalse);
      expect(const ScriptInfo(version: 2).current, isTrue);
    });
  });
}
