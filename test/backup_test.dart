import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rekap_rapi/backup/apps_script_client.dart';
import 'package:rekap_rapi/backup/backup_settings.dart';
import 'package:rekap_rapi/backup/backup_sheets.dart';
import 'package:rekap_rapi/cash/cash_models.dart';
import 'package:rekap_rapi/debts/debt_models.dart';

const _goodUrl = 'https://script.google.com/macros/s/AKfycbxABC_123-def/exec';

Debt _debt({
  required String id,
  required String contactId,
  required String kind,
  required int amount,
  required int paid,
  required bool cashMoved,
  required DateTime date,
  DateTime? due,
  bool isSale = false,
  int cost = 0,
  int discount = 0,
  int fee = 0,
  String? note,
}) =>
    Debt(
      id: id,
      contactId: contactId,
      kind: kind,
      amount: amount,
      cashMoved: cashMoved,
      debtDate: date,
      dueDate: due,
      note: note,
      createdBy: 'u1',
      createdAt: date,
      paid: paid,
      remaining: amount - paid,
      isSale: isSale,
      costAmount: cost,
      discountAmount: discount,
      extraFee: fee,
    );

BackupData _data() {
  final today = DateTime.now();
  final longAgo = DateTime(2020, 1, 5);
  return BackupData(
    businessName: 'Toko "Rapi" [A]',
    generatedAt: DateTime(2026, 11, 3, 14, 5),
    generatedBy: 'Budi',
    summary: const Summary(
      totalIn: 500000,
      totalOut: 120000,
      balance: 380000,
      receivableOpen: 60000,
      payableOpen: 40000,
      salesTotal: 300000,
      profit: 90000,
    ),
    cash: [
      CashTx(
        id: 't1',
        type: 'in',
        amount: 95000, // 100.000 - diskon 10.000 + ongkir 5.000
        date: DateTime(2026, 11, 1),
        note: '=HYPERLINK("http://x")',
        categoryId: 'c1',
        createdBy: 'u1',
        isSale: true,
        costAmount: 60000,
        discountAmount: 10000,
        extraFee: 5000,
      ),
      CashTx(
        id: 't2',
        type: 'out',
        amount: 20000,
        date: DateTime(2026, 11, 2),
        categoryId: 'c2',
        createdBy: 'u2',
      ),
      CashTx(
        id: 't3',
        type: 'in',
        amount: 30000,
        date: DateTime(2026, 11, 3),
        categoryId: 'c3',
        debtPaymentId: 'p1',
        createdBy: 'u1',
      ),
    ],
    categories: {'c1': 'Penjualan', 'c2': 'Gaji', 'c3': 'Pelunasan Piutang'},
    memberNames: {'u1': 'Budi', 'u2': 'Sari'},
    debts: [
      _debt(
          id: 'd1',
          contactId: 'k1',
          kind: 'receivable',
          amount: 90000,
          paid: 30000,
          cashMoved: false,
          date: DateTime(2026, 10, 20),
          due: longAgo,
          isSale: true,
          cost: 40000,
          note: 'kredit'),
      _debt(
          id: 'd2',
          contactId: 'k2',
          kind: 'payable',
          amount: 40000,
          paid: 0,
          cashMoved: true,
          date: today,
          due: today.add(const Duration(days: 10))),
      _debt(
          id: 'd3',
          contactId: 'k1',
          kind: 'receivable',
          amount: 10000,
          paid: 10000,
          cashMoved: true,
          date: DateTime(2026, 9, 1)),
    ],
    contacts: const [
      Contact('k1', 'Bu Evi', '0811223344',
          address: 'Jl. Mawar 1', note: 'langganan'),
      Contact('k2', 'Pak Budi', null),
      Contact('k3', 'Tanpa Transaksi', '+62812'),
    ],
    payments: [
      {
        'debt_id': 'd1',
        'amount': 30000,
        'paid_on': '2026-11-03',
        'note': null,
        'created_by': 'u1',
        'method': 'cash'
      },
      {
        'debt_id': 'd3',
        'amount': 10000,
        'paid_on': '2026-09-02',
        'note': 'lunas',
        'created_by': 'u2',
        'method': 'cash'
      },
      {
        'debt_id': 'd2',
        'amount': 5000,
        'paid_on': '2026-10-01',
        'note': 'x',
        'created_by': 'u1',
        'method': 'offset'
      },
      {
        'debt_id': 'hilang',
        'amount': 1,
        'paid_on': '2026-01-01',
        'note': null,
        'created_by': null,
        'method': 'cash'
      },
    ],
  );
}

void main() {
  group('buildBackupSheets', () {
    final sheets = buildBackupSheets(_data());
    BackupSheet sheet(String n) => sheets.firstWhere((s) => s.name == n);

    test('urutan dan nama lembar', () {
      expect(sheets.map((s) => s.name), [
        'Info',
        'Ringkasan',
        'Kas',
        'Piutang',
        'Utang',
        'Pembayaran',
        'Kontak'
      ]);
    });

    test('setiap baris sepanjang judul kolomnya dan kolom teks valid', () {
      for (final s in sheets) {
        final width = s.rows.first.length;
        for (final r in s.rows) {
          expect(r.length, width, reason: '${s.name}: lebar baris tidak sama');
        }
        for (final c in s.textColumns) {
          expect(c, inInclusiveRange(0, width - 1),
              reason: '${s.name}: kolom teks $c');
        }
        // Nilai harus bisa dikirim sebagai JSON.
        expect(() => jsonEncode(s.toJson()), returnsNormally);
      }
    });

    test('Info memuat usaha, waktu, pembuat, dan jumlah', () {
      final rows = {for (final r in sheet('Info').rows.skip(1)) r[0]: r[1]};
      expect(rows['Usaha'], 'Toko "Rapi" [A]');
      expect(rows['Waktu backup'], '2026-11-03 14:05');
      expect(rows['Dibackup oleh'], 'Budi');
      expect(rows['Jumlah transaksi kas'], 3);
      expect(rows['Jumlah catatan utang piutang'], 3);
      expect(rows['Jumlah kontak'], 3);
    });

    test('Ringkasan memakai angka dari ringkasan', () {
      final rows = {
        for (final r in sheet('Ringkasan').rows.skip(1)) r[0]: r[1]
      };
      expect(rows['Saldo kas saat ini'], 380000);
      expect(rows['Keuntungan penjualan (semua waktu)'], 90000);
      expect(rows['Piutang belum lunas'], 60000);
      expect(rows['Utang belum lunas'], 40000);
    });

    test('Kas: penjualan membawa modal, diskon, ongkir, dan keuntungan', () {
      final kas = sheet('Kas').rows;
      final sale = kas[1];
      expect(sale.sublist(0, 4), ['2026-11-01', 'Masuk', 'Penjualan', 95000]);
      // Total penjualan 100.000, modal 60.000, diskon 10.000, ongkir 5.000, untung 30.000.
      expect(sale.sublist(7), [100000, 60000, 10000, 5000, 35000]);
      expect(sale[6], 'Manual');

      final plain = kas[2];
      expect(plain.sublist(7), ['', '', '', '', ''],
          reason: 'bukan penjualan: kosong');
      expect(plain[5], 'Sari');

      final auto = kas[3];
      expect(auto[6], 'Otomatis (utang piutang)');
    });

    test('Kas: catatan berawalan "=" ada di kolom teks', () {
      final kas = sheet('Kas');
      expect(kas.rows[1][4], '=HYPERLINK("http://x")');
      expect(kas.textColumns, contains(4),
          reason: 'agar tidak dijalankan sebagai rumus');
    });

    test('Piutang dan Utang terpisah dengan status dan keuntungan', () {
      final piutang = sheet('Piutang').rows;
      // Diurutkan menurut tanggal: d3 (1 Sep) lalu d1 (20 Okt).
      expect(piutang[1][1], 'Bu Evi');
      expect(piutang[1][6], 'Lunas');
      expect(piutang[1][9], 'Uang');
      final sale = piutang[2];
      expect(sale.sublist(2, 5), [90000, 30000, 60000]);
      expect(sale[6], 'Lewat tempo');
      expect(sale[9], 'Penjualan');
      expect(sale.sublist(10), [40000, 0, 0, 50000]);

      final utang = sheet('Utang').rows;
      expect(utang, hasLength(2));
      expect(utang[1][1], 'Pak Budi');
      expect(utang[1][6], 'Belum lunas');
    });

    test('Pembayaran: tunai dan kompensasi, yatim dilewati, terurut tanggal',
        () {
      final p = sheet('Pembayaran').rows;
      expect(p, hasLength(4)); // judul + 3 (yang tanpa catatan utang dibuang)
      expect(p[1][0], '2026-09-02');
      expect(p[1].sublist(1, 5), ['Bu Evi', 'Piutang', 10000, 'Uang']);
      expect(p[2].sublist(1, 5), ['Pak Budi', 'Utang', 5000, 'Kompensasi']);
      expect(p[3][0], '2026-11-03');
    });

    test('Kontak: nomor tetap teks dan saldo bersih dihitung', () {
      final k = sheet('Kontak');
      expect(k.rows[1].sublist(0, 4),
          ['Bu Evi', '0811223344', 'Jl. Mawar 1', 'langganan']);
      expect(k.rows[1].sublist(4), [60000, 0, 60000]);
      expect(k.rows[2].sublist(4), [0, 40000, -40000]);
      expect(k.rows[3].sublist(4), [0, 0, 0]);
      expect(k.textColumns, containsAll([0, 1, 2, 3]));
    });

    test('data kosong tetap menghasilkan lembar berjudul', () {
      final empty = buildBackupSheets(BackupData(
        businessName: 'Kosong',
        generatedAt: DateTime(2026, 1, 1),
        generatedBy: '-',
        summary: const Summary(
            totalIn: 0,
            totalOut: 0,
            balance: 0,
            receivableOpen: 0,
            payableOpen: 0),
        cash: const [],
        categories: const {},
        memberNames: const {},
        debts: const [],
        contacts: const [],
        payments: const [],
      ));
      for (final s in empty) {
        expect(s.rows, isNotEmpty);
        if (!['Info', 'Ringkasan'].contains(s.name)) expect(s.dataRows, 0);
      }
    });
  });

  group('alamat skrip dan kode rahasia', () {
    test('alamat yang sah', () {
      expect(isValidScriptUrl(_goodUrl), isTrue);
      expect(isValidScriptUrl('  $_goodUrl  '), isTrue);
      expect(
          isValidScriptUrl(
              'https://script.google.com/a/macros/contoh.com/s/AKfy_1-x/exec'),
          isTrue);
    });

    test('alamat yang ditolak', () {
      for (final bad in [
        '',
        'http://script.google.com/macros/s/AKfy/exec',
        'https://contoh.evil.com/macros/s/AKfy/exec',
        'https://script.google.com/macros/s/AKfy/dev',
        'https://script.google.com/macros/s/AKfy/exec?x=1',
        'https://script.google.com/macros/s/AKfy/exec/../x',
        'https://script.google.com.evil.com/macros/s/AKfy/exec',
        'script.google.com/macros/s/AKfy/exec',
      ]) {
        expect(isValidScriptUrl(bad), isFalse, reason: bad);
      }
    });

    test('kode rahasia 32 karakter alfanumerik dan berbeda tiap kali', () {
      final a = generateBackupToken();
      final b = generateBackupToken();
      expect(a, hasLength(32));
      expect(RegExp(r'^[A-Za-z0-9]{32}$').hasMatch(a), isTrue);
      expect(a, isNot(b));
      expect(generateBackupToken(Random(1)), generateBackupToken(Random(1)));
    });
  });

  group('AppsScriptClient', () {
    final sheets = [
      const BackupSheet('Kas', [
        ['Tanggal', 'Jumlah'],
        ['2026-11-01', 1000],
      ], textColumns: [
        0
      ]),
    ];
    const okJson =
        '{"ok":true,"spreadsheetUrl":"https://docs.google.com/spreadsheets/d/F/edit",'
        '"sheets":{"Kas":1,"Kontak":3}}';

    test(
        'mengirim sebagai text/plain dengan token dan lembar, mengikuti pengalihan',
        () async {
      http.BaseRequest? sent;
      String? sentBody;
      Uri? followed;
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          sent = req;
          sentBody = req.body;
          return http.Response('', 302, headers: {
            'location': 'https://script.googleusercontent.com/macros/echo?id=1'
          });
        }
        followed = req.url;
        return http.Response(okJson, 200);
      });
      final r =
          await AppsScriptClient(client: client).send(_goodUrl, 'tok', sheets);

      expect(sent!.headers['Content-Type'], startsWith('text/plain'));
      final body = jsonDecode(sentBody!) as Map<String, dynamic>;
      expect(body['token'], 'tok');
      expect((body['sheets'] as List).single['name'], 'Kas');
      expect((body['sheets'] as List).single['textColumns'], [0]);
      expect(followed.toString(),
          startsWith('https://script.googleusercontent.com/'));
      expect(r.sheets, {'Kas': 1, 'Kontak': 3});
      expect(r.totalRows, 4);
      expect(r.spreadsheetUrl,
          startsWith('https://docs.google.com/spreadsheets/'));
    });

    test('jawaban langsung 200 tanpa pengalihan juga diterima', () async {
      final client = MockClient((_) async => http.Response(okJson, 200));
      final r =
          await AppsScriptClient(client: client).send(_goodUrl, 't', sheets);
      expect(r.totalRows, 4);
    });

    test('kode rahasia salah: pesan dari skrip diteruskan', () async {
      final client = MockClient((_) async => http.Response(
          '{"ok":false,"error":"Kode rahasia tidak cocok."}', 200));
      await expectLater(
        AppsScriptClient(client: client).send(_goodUrl, 'salah', sheets),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'message', 'Kode rahasia tidak cocok.')),
      );
    });

    test('jawaban HTML (akses bukan "Siapa saja") memberi petunjuk', () async {
      final client =
          MockClient((_) async => http.Response('<html>Sign in</html>', 200));
      await expectLater(
        AppsScriptClient(client: client).send(_goodUrl, 't', sheets),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'message', contains('Siapa saja'))),
      );
    });

    test('alamat tidak sah ditolak tanpa menghubungi jaringan', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response(okJson, 200);
      });
      await expectLater(
        AppsScriptClient(client: client)
            .send('https://contoh.evil.com/exec', 't', sheets),
        throwsA(isA<BackupException>()),
      );
      expect(called, isFalse);
    });

    test('tanpa internet', () async {
      final client =
          MockClient((_) async => throw http.ClientException('gagal'));
      await expectLater(
        AppsScriptClient(client: client).send(_goodUrl, 't', sheets),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'message', contains('koneksi internet'))),
      );
    });

    test('terlalu lama menjawab', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return http.Response(okJson, 200);
      });
      await expectLater(
        AppsScriptClient(
                client: client, timeout: const Duration(milliseconds: 50))
            .send(_goodUrl, 't', sheets),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'message', contains('terlalu lama'))),
      );
    });

    test('ping mengembalikan alamat spreadsheet dan tidak mengirim lembar',
        () async {
      String? body;
      final client = MockClient((req) async {
        body = req.body;
        return http.Response(
            '{"ok":true,"ping":true,"spreadsheetUrl":"https://docs.google.com/spreadsheets/d/F/edit"}',
            200);
      });
      final url = await AppsScriptClient(client: client).ping(_goodUrl, 'tok');
      expect(url, startsWith('https://docs.google.com/'));
      final j = jsonDecode(body!) as Map<String, dynamic>;
      expect(j['ping'], isTrue);
      expect(j.containsKey('sheets'), isFalse);
    });
  });

  test('berkas skrip memuat tepat satu penanda kode rahasia', () {
    final code = File('assets/backup_apps_script.gs').readAsStringSync();
    expect('__KODE_RAHASIA__'.allMatches(code), hasLength(1));
    expect(code, contains('function doPost'));
    expect(code, contains('function doGet'));
  });

  // Menulis payload nyata agar bisa diuji ke skrip Google Apps Script dengan Node
  // (lihat scratchpad/harness). Tidak memeriksa apa pun selain bahwa berkas tertulis.
  test('menulis payload contoh untuk uji skrip', () {
    final payload = {
      'sheets': [for (final s in buildBackupSheets(_data())) s.toJson()],
    };
    final dir = Directory('build/backup_test')..createSync(recursive: true);
    final file = File('${dir.path}/payload.json')
      ..writeAsStringSync(jsonEncode(payload));
    expect(file.existsSync(), isTrue);
  });
}
