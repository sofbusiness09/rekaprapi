import 'package:flutter_test/flutter_test.dart';
import 'package:rekap_rapi/auth/url_auth_hint.dart';

void main() {
  UrlAuthHint hint(String url) => UrlAuthHint.parse(Uri.parse(url));

  test('tautan reset password di fragmen dikenali', () {
    final h = hint(
        'https://a.github.io/rekaprapi/#access_token=abc&refresh_token=x&type=recovery');
    expect(h.recovery, isTrue);
    expect(h.error, isNull);
  });

  test('tautan reset dengan fragmen berawalan garis miring dikenali', () {
    expect(hint('https://a.io/#/?access_token=abc&type=recovery').recovery,
        isTrue);
  });

  test('tautan kedaluwarsa memberi pesan, bukan layar reset', () {
    final h = hint(
        'https://a.io/rekaprapi/#error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid');
    expect(h.recovery, isFalse);
    expect(h.error, contains('kedaluwarsa'));
  });

  test('galat lain tetap memberi pesan umum', () {
    expect(hint('https://a.io/?error=server_error').error,
        contains('tidak dapat dipakai'));
  });

  test('alamat biasa dan rute hash tidak memicu apa pun', () {
    for (final url in [
      'https://a.io/rekaprapi/',
      'https://a.io/rekaprapi/#/',
      'https://a.io/rekaprapi/#/kas',
      'http://localhost:5000/',
    ]) {
      final h = hint(url);
      expect(h.recovery, isFalse, reason: url);
      expect(h.error, isNull, reason: url);
    }
  });

  test('tautan masuk biasa bukan pemulihan', () {
    expect(hint('https://a.io/#access_token=abc&type=signup').recovery,
        isFalse);
  });
}
