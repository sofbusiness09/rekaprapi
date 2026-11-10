import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/telegram/telegram_page.dart';

class _FakeRepo extends TelegramRepository {
  _FakeRepo(this.current);

  TelegramStatus current;
  String? createdFor;
  bool unlinked = false;

  @override
  Future<TelegramStatus> status() async => current;

  @override
  Future<Uri> createLink(String businessId) async {
    createdFor = businessId;
    return telegramStartLink('UjiBot', 'kode123');
  }

  @override
  Future<void> unlink() async {
    unlinked = true;
    current = TelegramStatus(bot: current.bot);
  }
}

Future<void> _pump(WidgetTester tester, _FakeRepo repo,
    {List<Uri>? opened}) async {
  await tester.pumpWidget(MaterialApp(
    home: TelegramPage(
      businessId: 'b1',
      businessName: 'Toko',
      repo: repo,
      opener: (u) async {
        opened?.add(u);
        return opened != null;
      },
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('alamat pembuka bot memuat kode', () {
    expect('${telegramStartLink('RekapBot', 'abc')}',
        'https://t.me/RekapBot?start=abc');
  });

  test('status dibaca dari jawaban database', () {
    final s = TelegramStatus.fromMap(
        {'bot': 'RekapBot', 'linked': true, 'name': 'Ani'});
    expect((s.bot, s.linked, s.name), ('RekapBot', true, 'Ani'));
    expect(TelegramStatus.fromMap({'bot': null}).linked, isFalse);
  });

  testWidgets('bot belum diaktifkan: tidak ada tombol Hubungkan',
      (tester) async {
    await _pump(tester, _FakeRepo(const TelegramStatus()));
    expect(find.text('Bot Telegram belum diaktifkan'), findsOneWidget);
    expect(find.text('Hubungkan'), findsNothing);
  });

  testWidgets('Hubungkan membuat kode untuk pembukuan ini dan membuka bot',
      (tester) async {
    final repo = _FakeRepo(const TelegramStatus(bot: 'UjiBot'));
    final opened = <Uri>[];
    await _pump(tester, repo, opened: opened);
    expect(find.text('Belum terhubung'), findsOneWidget);

    await tester.tap(find.text('Hubungkan'));
    await tester.pumpAndSettle();
    expect(repo.createdFor, 'b1');
    expect('${opened.single}', 'https://t.me/UjiBot?start=kode123');
    expect(find.text('https://t.me/UjiBot?start=kode123'), findsOneWidget);

    // Setelah Start ditekan di Telegram, Periksa menampilkan Terhubung.
    repo.current =
        const TelegramStatus(bot: 'UjiBot', linked: true, name: 'Ani');
    await tester.tap(find.text('Periksa'));
    await tester.pumpAndSettle();
    expect(find.text('Terhubung'), findsOneWidget);
    expect(find.text('Ani · @UjiBot'), findsOneWidget);
  });

  testWidgets('Telegram tidak terbuka: alamat tetap bisa disalin',
      (tester) async {
    final repo = _FakeRepo(const TelegramStatus(bot: 'UjiBot'));
    await _pump(tester, repo); // opener mengembalikan false
    await tester.tap(find.text('Hubungkan'));
    await tester.pumpAndSettle();
    expect(find.text('Salin'), findsOneWidget);
    expect(find.textContaining('Telegram tidak terbuka'), findsOneWidget);
  });

  testWidgets('Putuskan meminta konfirmasi lalu memutuskan', (tester) async {
    final repo =
        _FakeRepo(const TelegramStatus(bot: 'UjiBot', linked: true, name: 'A'));
    await _pump(tester, repo);
    await tester.tap(find.text('Putuskan'));
    await tester.pumpAndSettle();
    expect(repo.unlinked, isFalse);
    await tester.tap(find.text('Putuskan').last);
    await tester.pumpAndSettle();
    expect(repo.unlinked, isTrue);
    expect(find.text('Belum terhubung'), findsOneWidget);
  });
}
