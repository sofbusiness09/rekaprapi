import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business_gate.dart';
import 'login_page.dart';

/// Menampilkan halaman masuk atau pemilih usaha sesuai status sesi.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, _) {
        return auth.currentSession == null
            ? const LoginPage()
            : const BusinessGate();
      },
    );
  }
}
