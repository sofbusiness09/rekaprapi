import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../common/widgets.dart';
import '../theme/app_theme.dart';
import 'url_auth_hint.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

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
      _toast('Isi email yang valid dan password minimal 6 karakter.');
      return;
    }
    setState(() => _busy = true);
    final auth = Supabase.instance.client.auth;
    try {
      if (_register) {
        await auth.signUp(email: email, password: password);
        _toast('Akun dibuat. Silakan masuk.');
        setState(() => _register = false);
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      _toast('Isi email dulu.');
      return;
    }
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      _toast('Tautan reset password dikirim ke email Anda.');
    } on AuthException catch (e) {
      _toast(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Brand.seed.withValues(alpha: 0.14),
              theme.scaffoldBackgroundColor,
            ],
            stops: const [0, 0.5],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ContentWidth(
                maxWidth: 420,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Logo RekapRapi (lambang + tulisan) pada kartu hijau tua seperti aslinya.
                  Container(
                    width: 280,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                            color: Brand.deep.withValues(alpha: 0.35),
                            blurRadius: 24,
                            offset: const Offset(0, 12)),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/logo/logo_full.png',
                      fit: BoxFit.fitWidth,
                      semanticLabel: 'RekapRapi',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Catat kas dan utang piutang usaha, rapi dan cepat.',
                      textAlign: TextAlign.center,
                      style:
                          theme.textTheme.bodyMedium?.copyWith(color: muted)),
                  const SizedBox(height: 28),
                  SoftCard(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(_register ? 'Buat akun baru' : 'Masuk',
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            obscureText: _hide,
                            autofillHints: const [AutofillHints.password],
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon:
                                  const Icon(Icons.lock_outline_rounded),
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
                                : Text(_register ? 'Daftar' : 'Masuk'),
                          ),
                          if (!_register)
                            Align(
                              alignment: Alignment.center,
                              child: TextButton(
                                  onPressed: _busy ? null : _resetPassword,
                                  child: const Text('Lupa password?')),
                            ),
                        ]),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _register = !_register),
                    child: Text(_register
                        ? 'Sudah punya akun? Masuk'
                        : 'Belum punya akun? Daftar'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
