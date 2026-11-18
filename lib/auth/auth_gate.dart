import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business_gate.dart';
import '../update/app_update.dart';
import 'login_page.dart';
import 'reset_code_page.dart';
import 'reset_password_page.dart';
import 'url_auth_hint.dart';

/// Menampilkan halaman masuk, layar password baru, atau pemilih usaha sesuai status sesi.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Dibuka dari tautan reset password: tampilkan layar password baru dulu.
  bool _recovering = UrlAuthHint.current.recovery;
  StreamSubscription<AuthState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      // Ganti password lewat kode di aplikasi tidak perlu layar password baru lagi.
      if (state.event == AuthChangeEvent.passwordRecovery &&
          !_recovering &&
          !PasswordResetFlow.active) {
        setState(() => _recovering = true);
      }
    });
    // Aplikasi Android: tawarkan pembaruan bila ada versi baru di GitHub.
    if (updatesSupported) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) maybeShowUpdate(context);
      });
    }
    // Tautan email yang gagal (kedaluwarsa atau sudah terpakai) saat peramban sudah
    // masuk: halaman login tidak tampil, jadi alasannya diberitahukan di sini.
    final problem = UrlAuthHint.current.error;
    if (problem != null &&
        Supabase.instance.client.auth.currentSession != null) {
      UrlAuthHint.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Tautan tidak berlaku'),
            content: Text('$problem Password Anda tidak berubah.'),
            actions: [
              FilledButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Mengerti')),
            ],
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _recoveryDone() {
    UrlAuthHint.clear();
    setState(() => _recovering = false);
  }

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        if (auth.currentSession == null) return const LoginPage();
        if (_recovering) return ResetPasswordPage(onDone: _recoveryDone);
        return const BusinessGate();
      },
    );
  }
}
