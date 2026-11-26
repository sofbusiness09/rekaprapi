import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../common/widgets.dart';
import 'reset_code_page.dart';
import 'url_auth_hint.dart';
import 'package:rekap_rapi/l10n/l10n.dart';

class LoginPage extends StatefulWidget {
  const LoginPage(
      {super.key, this.resetActions = const PasswordResetActions()});

  final PasswordResetActions resetActions;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  bool _hide = true;

  @override
  void initState() {
    super.initState();
    // Tautan email yang ditolak (kedaluwarsa atau sudah terpakai) menjelaskan alasannya.
    final problem = UrlAuthHint.current.error;
    if (problem != null) {
      UrlAuthHint.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _toast(problem);
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || password.length < 6) {
      _toast(tr('Isi email yang valid dan password minimal 6 karakter.'));
      return;
    }
    setState(() => _busy = true);
    final auth = Supabase.instance.client.auth;
    try {
      if (_register) {
        await auth.signUp(email: email, password: password);
        _toast(tr('Akun dibuat. Silakan masuk.'));
        setState(() => _register = false);
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(tr('Gagal: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Lupa password: kode dikirim ke email, lalu diisi di aplikasi bersama password baru.
  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      _toast(tr('Isi email dulu.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.resetActions.sendCode(email);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            ResetCodePage(email: email, actions: widget.resetActions),
      ));
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast(tr('Gagal mengirim kode: {0}', [e]));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ContentWidth(
              maxWidth: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Lambang yang sama dengan ikon aplikasi, lalu nama di bawahnya.
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 96,
                    height: 96,
                    semanticLabel: tr('RekapRapi'),
                  ),
                ),
                const SizedBox(height: 16),
                Text(tr('RekapRapi'),
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(tr('Catat kas dan utang piutang usaha, rapi dan cepat.'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                const SizedBox(height: 28),
                SoftCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(_register ? tr('Buat akun baru') : tr('Masuk'),
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: InputDecoration(
                            labelText: tr('Email'),
                            prefixIcon: const Icon(Icons.mail_outline_rounded),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: _hide,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: tr('Password'),
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              icon: Icon(_hide
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _hide = !_hide),
                            ),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _submit,
                          child: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.white))
                              : Text(_register ? tr('Daftar') : tr('Masuk')),
                        ),
                        if (!_register)
                          Align(
                            alignment: Alignment.center,
                            child: TextButton(
                                onPressed: _busy ? null : _resetPassword,
                                child: Text(tr('Lupa password?'))),
                          ),
                      ]),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _register = !_register),
                  child: Text(_register
                      ? tr('Sudah punya akun? Masuk')
                      : tr('Belum punya akun? Daftar')),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
