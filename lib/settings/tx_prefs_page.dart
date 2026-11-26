import 'package:flutter/material.dart';

import '../common/widgets.dart';
import 'home_prefs.dart';
import 'package:rekap_rapi/l10n/l10n.dart';

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
      appBar: AppBar(title: Text(tr('Tampilan Transaksi'))),
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
                subtitle: subtitle.isEmpty ? null : Text(subtitle),
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
                        ? tr('Berlaku untuk usaha yang sedang dibuka.')
                        : tr('Berlaku untuk usaha "{0}".', [businessName]),
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
                SectionTitle(tr('Transaksi kas')),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    toggle(tr('Pemasukan'), '', p.txIn,
                        (v) => set(p.copyWith(txIn: v))),
                    const Divider(),
                    toggle(tr('Pengeluaran'), '', p.txOut,
                        (v) => set(p.copyWith(txOut: v))),
                  ]),
                ),
                SectionTitle(tr('Catatan utang piutang')),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    toggle(tr('Transaksi hutang'), '', p.txCredit,
                        (v) => set(p.copyWith(txCredit: v))),
                    const Divider(),
                    toggle(
                        tr('Kas dari utang piutang'),
                        'Pelunasan, pembayaran, pemberian, penerimaan',
                        p.txDebtCash,
                        (v) => set(p.copyWith(txDebtCash: v))),
                  ]),
                ),
                if (!p.txIn && !p.txOut && !p.txCredit && !p.txDebtCash)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                    child: Text(
                      tr('Semua dimatikan, jadi daftar Transaksi akan kosong.'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: Text(
                    tr('Saldo dan rekapan tetap menghitung semuanya.'),
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
                    messenger.showSnackBar(SnackBar(
                        content: Text(tr('Dikembalikan ke tampilan bawaan.'))));
                  },
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: Text(tr('Kembalikan ke bawaan')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
