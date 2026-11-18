import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../common/widgets.dart';
import '../config.dart';
import '../theme/app_theme.dart';

/// Penanda bahwa ganti password sedang berlangsung lewat kode di aplikasi. Selama
/// aktif, AuthGate tidak membuka layar "password baru" dari tautan email, karena
/// password sudah diganti di halaman kode.
class PasswordResetFlow {
  static bool active = false;
}

/// Aksi Supabase untuk lupa password. Dapat diganti tiruan saat diuji.
class PasswordResetActions {
  const PasswordResetActions();

  GoTrueClient get _auth => Supabase.instance.client.auth;

  /// Mengirim email berisi kode. Alamat kembali tetap diisi agar email lama yang
  /// masih memakai tautan tetap bisa dipakai.
  Future<void> sendCode(String email) => _auth.resetPasswordForEmail(email,
      redirectTo: kIsWeb ? '${Uri.base.origin}${Uri.base.path}' : webAppUrl);

  /// Memeriksa kode; bila benar, pengguna masuk dengan sesi pemulihan.
  Future<void> verify(String email, String code) =>
      _auth.verifyOTP(type: OtpType.recovery, email: email, token: code);

  Future<void> setPassword(String password) =>
      _auth.updateUser(UserAttributes(password: password));
}

/// Kode dari email: hanya angka, 6 sampai 10 digit (mengikuti pengaturan Supabase).
bool isResetCode(String s) => RegExp(r'^\d{6,10}$').hasMatch(s);

/// Lupa password: masukkan kode dari email dan password baru, semuanya di aplikasi.
class ResetCodePage extends StatefulWidget {
  const ResetCodePage({
    super.key,
    required this.email,
    this.actions = const PasswordResetActions(),
    this.resendAfter = const Duration(seconds: 60),
  });

  final String email;
  final PasswordResetActions actions;

  /// Jeda sebelum kode baru boleh diminta lagi.
  final Duration resendAfter;

  @override
  State<ResetCodePage> createState() => _ResetCodePageState();
}

class _ResetCodePageState extends State<ResetCodePage> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  int _wait = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startWait();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    PasswordResetFlow.active = false;
    super.dispose();
  }

  void _startWait() {
    _timer?.cancel();
    _wait = widget.resendAfter.inSeconds;
    if (_wait <= 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  void _toast(String msg) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _resend() async {
    setState(() => _busy = true);
    try {
      await widget.actions.sendCode(widget.email);
      if (!mounted) return;
      _toast('Kode baru dikirim. Kode lama tidak berlaku lagi.');
      setState(_startWait);
    } on AuthException catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final code = _code.text.trim();
    if (!isResetCode(code)) {
      _toast('Isi kode angka dari email.');
      return;
    }
    if (_password.text.length < 6) {
      _toast('Password minimal 6 karakter.');
      return;
    }
    if (_password.text != _confirm.text) {
      _toast('Konfirmasi password tidak sama.');
      return;
    }
    setState(() => _busy = true);
    PasswordResetFlow.active = true;
    try {
      await widget.actions.verify(widget.email, code);
    } on AuthException catch (e) {
      PasswordResetFlow.active = false;
      if (mounted) {
        setState(() => _busy = false);
        _toast(_codeError(e));
      }
      return;
    }
    try {
      await widget.actions.setPassword(_password.text);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).popUntil((r) => r.isFirst);
      messenger.showSnackBar(
          const SnackBar(content: Text('Password diganti. Anda sudah masuk.')));
    } on AuthException catch (e) {
      // Kode sudah benar dan pengguna sudah masuk; password lama tetap berlaku.
      if (mounted) {
        setState(() => _busy = false);
        _toast('Password belum diganti: ${e.message}');
      }
    } finally {
      PasswordResetFlow.active = false;
    }
  }

  String _codeError(AuthException e) {
    final m = e.message.toLowerCase();
    if (m.contains('expired') || m.contains('invalid') || m.contains('token')) {
      return 'Kode salah atau sudah kedaluwarsa. Periksa lagi, atau minta kode baru.';
    }
    return e.message;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(title: const Text('Lupa password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ContentWidth(
              maxWidth: 420,
              child: SoftCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: IconBadge(Icons.lock_reset_rounded,
                          color: Brand.seed, size: 56),
                    ),
                    const SizedBox(height: 16),
                    Text('Masukkan kode dari email',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('Kode dikirim ke ${widget.email}.',
                        textAlign: TextAlign.center,
                        style:
                            theme.textTheme.bodyMedium?.copyWith(color: muted)),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _code,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 10,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: theme.textTheme.headlineSmall?.copyWith(
                          letterSpacing: 6, fontWeight: FontWeight.w600),
                      decoration: const InputDecoration(
                        labelText: 'Kode',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: _hide,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Password baru',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        suffixIcon: IconButton(
                          icon: Icon(_hide
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _hide = !_hide),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirm,
                      obscureText: _hide,
                      decoration: const InputDecoration(
                        labelText: 'Ulangi password baru',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                      onSubmitted: (_) => _busy ? null : _save(),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white))
                          : const Text('Simpan password'),
                    ),
                    TextButton(
                      onPressed: _busy || _wait > 0 ? null : _resend,
                      child: Text(_wait > 0
                          ? 'Kirim ulang kode ($_wait)'
                          : 'Kirim ulang kode'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
