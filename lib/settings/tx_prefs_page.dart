import 'package:flutter/material.dart';

import '../common/widgets.dart';
import 'home_prefs.dart';

/// Pengaturan > Tampilan Transaksi: apa saja yang tampil di tab Transaksi.
/// Bawaannya hanya pemasukan dan pengeluaran; catatan utang piutang tersembunyi.
/// Pilihan berlaku untuk usaha yang sedang dibuka.
class TxPrefsPage extends StatelessWidget {
  const TxPrefsPage({super.key, this.businessName});

  final String? businessName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Tampilan Transaksi')),
      body: ListenableBuilder(
        listenable: homePrefs,
        builder: (context, _) {
          final p = homePrefs.value;
          void set(HomePrefs next) => homePrefs.update(next);

          Widget toggle(String title, String subtitle, bool value,
                  ValueChanged<bool> onChanged) =>
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
                    businessName == null
                        ? 'Pilih apa yang tampil di daftar Transaksi.'
                        : 'Pilih apa yang tampil di daftar Transaksi usaha "$businessName". Usaha lain punya pilihan sendiri.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
                const SectionTitle('Transaksi kas'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    toggle('Pemasukan', 'Penjualan dan uang masuk lainnya',
                        p.txIn, (v) => set(p.copyWith(txIn: v))),
                    const Divider(),
                    toggle(
                        'Pengeluaran',
                        'Belanja stok, gaji, sewa, dan lainnya',
                        p.txOut,
                        (v) => set(p.copyWith(txOut: v))),
                  ]),
                ),
                const SectionTitle('Catatan utang piutang'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    toggle(
                        'Transaksi hutang',
                        'Penjualan atau pembelian kredit yang belum dibayar',
                        p.txCredit,
                        (v) => set(p.copyWith(txCredit: v))),
                    const Divider(),
                    toggle(
                        'Kas dari utang piutang',
                        'Pelunasan, pembayaran, pemberian, dan penerimaan utang yang otomatis masuk kas',
                        p.txDebtCash,
                        (v) => set(p.copyWith(txDebtCash: v))),
                  ]),
                ),
                if (!p.txIn && !p.txOut && !p.txCredit && !p.txDebtCash)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                    child: Text(
                      'Semua dimatikan, jadi daftar Transaksi akan kosong.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: Text(
                    'Menyembunyikan tidak menghapus apa pun. Saldo, laporan, dan menu Utang tetap menghitung semuanya.',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await homePrefs.update(homePrefs.value.copyWith(
                      txIn: true,
                      txOut: true,
                      txCredit: false,
                      txDebtCash: false,
                    ));
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
