/// Petunjuk dari alamat halaman saat aplikasi web dibuka lewat tautan email Supabase.
///
/// Tautan reset password berbentuk `.../#access_token=...&type=recovery`, dan tautan
/// yang gagal berbentuk `.../#error=access_denied&error_code=otp_expired&...`.
/// Dibaca sekali sebelum Supabase diinisialisasi, karena Supabase memakai lalu
/// membersihkan alamat itu, dan kejadian pemulihan sudah lewat sebelum layar dibangun.
class UrlAuthHint {
  const UrlAuthHint({this.recovery = false, this.error});

  /// Halaman dibuka dari tautan reset password.
  final bool recovery;

  /// Pesan untuk pengguna bila tautan ditolak (kedaluwarsa atau sudah terpakai).
  final String? error;

  static UrlAuthHint current = const UrlAuthHint();

  static void read(Uri uri) => current = parse(uri);

  static void clear() => current = const UrlAuthHint();

  static UrlAuthHint parse(Uri uri) {
    final params = <String, String>{};
    // Parameter bisa di query (?a=b) maupun di fragmen (#a=b atau #/?a=b).
    for (final raw in [uri.query, uri.fragment]) {
      final text = raw.replaceFirst(RegExp(r'^/?\??'), '');
      if (!text.contains('=')) continue;
      try {
        params.addAll(Uri.splitQueryString(text));
      } on FormatException {
        // Fragmen rute biasa seperti "/kas"; tidak ada petunjuk di sana.
      }
    }

    final code = params['error_code'];
    final hasError = params.containsKey('error') ||
        params.containsKey('error_description') ||
        code != null;
    if (hasError) {
      final expired = code == 'otp_expired';
      return UrlAuthHint(
        error: expired
            ? 'Tautan sudah kedaluwarsa atau sudah terpakai. Minta tautan baru.'
            : 'Tautan tidak dapat dipakai. Minta tautan baru.',
      );
    }
    return UrlAuthHint(recovery: params['type'] == 'recovery');
  }
}
