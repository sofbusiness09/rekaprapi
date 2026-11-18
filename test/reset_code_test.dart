import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/auth/reset_code_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeActions extends PasswordResetActions {
  final sent = <String>[];
  final verified = <(String, String)>[];
  String? password;
  bool wrongCode = false;
  bool activeDuringVerify = false;

  @override
  Future<void> sendCode(String email) async => sent.add(email);

  @override
  Future<void> verify(String email, String code) async {
    activeDuringVerify = PasswordResetFlow.active;
    if (wrongCode) {
      throw const AuthException('Token has expired or is invalid');
    }
    verified.add((email, code));
  }

  @override
  Future<void> setPassword(String password) async => this.password = password;
}

Future<void> _open(WidgetTester tester, _FakeActions actions) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => ResetCodePage(
                email: 'ani@contoh.id',
                actions: actions,
                resendAfter: const Duration(seconds: 2)),
          )),
          child: const Text('mulai'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('mulai'));
  await tester.pumpAndSettle();
}

Future<void> _fill(WidgetTester tester, String code, String pw,
    [String? confirm]) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(0), code);
  await tester.enterText(fields.at(1), pw);
  await tester.enterText(fields.at(2), confirm ?? pw);
  await tester.tap(find.text('Simpan password'));
  await tester.pumpAndSettle();
}

void main() {
  test('kode hanya angka 6 sampai 10 digit', () {
    expect(isResetCode('123456'), isTrue);
    expect(isResetCode('12345678'), isTrue);
    expect(isResetCode('12345'), isFalse);
    expect(isResetCode('12a456'), isFalse);
    expect(isResetCode(''), isFalse);
  });

  testWidgets('kode benar: password diganti dan halaman ditutup',
      (tester) async {
    final a = _FakeActions();
    await _open(tester, a);
    expect(find.text('Kode dikirim ke ani@contoh.id.'), findsOneWidget);
    await _fill(tester, '123456', 'rahasia1');
    expect(a.verified, [('ani@contoh.id', '123456')]);
    expect(a.password, 'rahasia1');
    // Selama memeriksa kode, layar "password baru" dari tautan tidak dibuka.
    expect(a.activeDuringVerify, isTrue);
    expect(PasswordResetFlow.active, isFalse);
    expect(find.text('mulai'), findsOneWidget);
    expect(find.text('Password diganti. Anda sudah masuk.'), findsOneWidget);
  });

  testWidgets('kode salah: pesan jelas, password tidak diganti',
      (tester) async {
    final a = _FakeActions()..wrongCode = true;
    await _open(tester, a);
    await _fill(tester, '000000', 'rahasia1');
    expect(a.password, isNull);
    expect(find.textContaining('Kode salah atau sudah kedaluwarsa'),
        findsOneWidget);
    expect(find.text('Simpan password'), findsOneWidget);
    expect(PasswordResetFlow.active, isFalse);
  });

  testWidgets('isian belum benar ditolak sebelum menghubungi server',
      (tester) async {
    final a = _FakeActions();
    await _open(tester, a);
    await _fill(tester, '123', 'rahasia1');
    expect(find.text('Isi kode angka dari email.'), findsOneWidget);
    await _fill(tester, '123456', '123');
    expect(find.text('Password minimal 6 karakter.'), findsOneWidget);
    await _fill(tester, '123456', 'rahasia1', 'rahasia2');
    expect(find.text('Konfirmasi password tidak sama.'), findsOneWidget);
    expect(a.verified, isEmpty);
  });

  testWidgets('kirim ulang kode setelah jeda', (tester) async {
    final a = _FakeActions();
    await _open(tester, a);
    final resend = find.widgetWithText(TextButton, 'Kirim ulang kode (2)');
    expect(tester.widget<TextButton>(resend).onPressed, isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.text('Kirim ulang kode'));
    await tester.pumpAndSettle();
    expect(a.sent, ['ani@contoh.id']);
    expect(find.textContaining('Kode baru dikirim'), findsOneWidget);
  });
}
