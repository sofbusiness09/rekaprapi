import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backup/restore_page.dart';

import '../common/widgets.dart';
import '../theme/app_theme.dart';
import 'business_controller.dart';
import 'business_home.dart';
import 'business_switcher.dart';

/// Setelah masuk: langsung membuka usaha terakhir. Layar "belum ada usaha"
/// hanya tampil bila pengguna belum punya usaha sama sekali.
class BusinessGate extends StatefulWidget {
  const BusinessGate({super.key});

  @override
  State<BusinessGate> createState() => _BusinessGateState();
}

class _BusinessGateState extends State<BusinessGate> {
  final _controller = BusinessController();

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        if (c.loading) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (c.error != null && c.current == null && c.businesses.isEmpty) {
          return Scaffold(
            body: Center(
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Gagal memuat usaha',
                subtitle: '${c.error}',
                actionLabel: 'Coba lagi',
                onAction: () => c.load(),
              ),
            ),
          );
        }
        final current = c.current;
        if (current == null) return _NoBusinessPage(controller: c);
        // Kunci per usaha: berpindah usaha membangun ulang semua halaman dan
        // koneksi realtime untuk usaha yang baru.
        return BusinessHome(
            key: ValueKey(current.id), business: current, controller: c);
      },
    );
  }
}

/// Tampil hanya bila pengguna belum punya usaha: buat pembukuan pertama atau terima undangan.
class _NoBusinessPage extends StatelessWidget {
  const _NoBusinessPage({required this.controller});

  final BusinessController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Scaffold(
      appBar: AppBar(
        title: const Text('RekapRapi'),
        actions: [
          IconButton(
            tooltip: 'Keluar',
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => Supabase.instance.client.auth.signOut(),
          ),
        ],
      ),
      body: ContentWidth(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            EmptyState(
              icon: Icons.storefront_rounded,
              title: 'Selamat datang!',
              subtitle:
                  'Buat pembukuan pertama Anda, atau gabung dengan kode undangan.',
              actionLabel: 'Buat pembukuan',
              onAction: () => promptCreateBusiness(context, controller),
            ),
            OutlinedButton.icon(
              onPressed: () => promptJoinByCode(context, controller),
              icon: const Icon(Icons.vpn_key_rounded),
              label: const Text('Gabung dengan kode'),
            ),
            const SizedBox(height: 8),
            // Akun baru atau pembukuan terhapus: pulihkan dari backup Google Sheet.
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    RestorePage(onRestored: controller.afterRestore),
              )),
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Pulihkan dari Google Sheet'),
            ),
            if (controller.invites.isNotEmpty) ...[
              const SectionTitle('Undangan untuk Anda'),
              for (final i in controller.invites)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const IconBadge(Icons.mail_rounded,
                              color: Brand.info),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(i.businessName,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600)),
                                Text(
                                    'Diundang sebagai ${roleNames[i.role] ?? i.role}',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: muted)),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44)),
                              onPressed: () => runWithToast(
                                  context, () => controller.decline(i.id)),
                              child: const Text('Tolak'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(44)),
                              onPressed: () => runWithToast(
                                  context, () => controller.accept(i.id),
                                  done: 'Berhasil bergabung.'),
                              child: const Text('Terima'),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
