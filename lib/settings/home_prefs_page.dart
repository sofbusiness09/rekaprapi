import 'package:flutter/material.dart';

import '../common/widgets.dart';
import 'home_prefs.dart';

/// Pengaturan > Tampilan Beranda: pilih bagian Beranda yang tampil dan jenis
/// aktivitas pada Aktivitas terbaru. Bawaannya menampilkan semuanya.
class HomePrefsPage extends StatelessWidget {
  const HomePrefsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Tampilan Beranda')),
      body: ListenableBuilder(
        listenable: homePrefs,
        builder: (context, _) {
          final p = homePrefs.value;
          void set(HomePrefs next) => homePrefs.update(next);

          Widget toggle(String title, String subtitle, bool value,
                  ValueChanged<bool>? onChanged) =>
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                title: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(subtitle),
                value: value,
                onChanged: onChanged,
              );

          return ContentWidth(
            maxWidth: 640,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  child: Text(
                    'Pilih apa yang ingin Anda lihat di Beranda. Pilihan tersimpan di akun Anda dan otomatis dipakai di semua perangkat.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
                const SectionTitle('Bagian Beranda'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    toggle('Saldo kas', 'Angka saldo kas saat ini',
                        p.showBalance, (v) => set(p.copyWith(showBalance: v))),
                    const Divider(),
                    toggle(
                        'Kas masuk dan keluar bulan ini',
                        'Total uang masuk dan keluar bulan berjalan',
                        p.showFlow,
                        (v) => set(p.copyWith(showFlow: v))),
                    const Divider(),
                    toggle(
                        'Keuntungan bulan ini',
                        'Keuntungan dari transaksi penjualan',
                        p.showProfit,
                        (v) => set(p.copyWith(showProfit: v))),
                    const Divider(),
                    toggle(
                        'Tombol cepat',
                        'Kas masuk, kas keluar, dan Utang',
                        p.showQuickActions,
                        (v) => set(p.copyWith(showQuickActions: v))),
                    const Divider(),
                    toggle(
                        'Piutang dan utang belum lunas',
                        'Total yang harus ditagih dan harus dibayar',
                        p.showDebtCards,
                        (v) => set(p.copyWith(showDebtCards: v))),
                    const Divider(),
                    toggle(
                        'Aktivitas terbaru',
                        'Daftar perputaran uang terakhir',
                        p.showActivity,
                        (v) => set(p.copyWith(showActivity: v))),
                  ]),
                ),
                if (!p.anySection)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                    child: Text(
                      'Semua bagian dimatikan, jadi Beranda akan kosong.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                const SectionTitle('Jenis aktivitas yang tampil'),
                Opacity(
                  opacity: p.showActivity ? 1 : 0.45,
                  child: SoftCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(children: [
                      toggle(
                          'Kas masuk',
                          'Pemasukan dan penjualan yang sudah lunas',
                          p.actCashIn,
                          p.showActivity
                              ? (v) => set(p.copyWith(actCashIn: v))
                              : null),
                      const Divider(),
                      toggle(
                          'Kas keluar',
                          'Pengeluaran yang sudah dibayar',
                          p.actCashOut,
                          p.showActivity
                              ? (v) => set(p.copyWith(actCashOut: v))
                              : null),
                      const Divider(),
                      toggle(
                          'Transaksi hutang',
                          'Penjualan atau pembelian kredit yang belum dibayar',
                          p.actCredit,
                          p.showActivity
                              ? (v) => set(p.copyWith(actCredit: v))
                              : null),
                      const Divider(),
                      toggle(
                          'Pelunasan dan pembayaran',
                          'Piutang yang diterima dan utang yang dibayar',
                          p.actPayments,
                          p.showActivity
                              ? (v) => set(p.copyWith(actPayments: v))
                              : null),
                      const Divider(),
                      toggle(
                          'Utang dan piutang berupa uang',
                          'Uang yang dipinjamkan atau diterima sebagai utang/modal',
                          p.actLoans,
                          p.showActivity
                              ? (v) => set(p.copyWith(actLoans: v))
                              : null),
                    ]),
                  ),
                ),
                if (p.showActivity && !p.anyActivityType)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                    child: Text(
                      'Semua jenis dimatikan, jadi Aktivitas terbaru akan kosong.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                const SectionTitle('Jumlah aktivitas'),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Tampilkan sampai',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: muted)),
                      const SizedBox(height: 10),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: [
                          for (final n in HomePrefs.countOptions)
                            ButtonSegment(value: n, label: Text('$n')),
                        ],
                        selected: {p.activityCount},
                        onSelectionChanged: p.showActivity
                            ? (s) => set(p.copyWith(activityCount: s.first))
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await homePrefs.reset();
                    messenger.showSnackBar(const SnackBar(
                        content: Text('Dikembalikan ke tampilan bawaan.')));
                  },
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Kembalikan ke bawaan'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
