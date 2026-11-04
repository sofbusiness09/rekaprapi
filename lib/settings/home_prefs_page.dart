import 'package:flutter/material.dart';

import '../common/widgets.dart';
import 'home_prefs.dart';

/// Pengaturan > Tampilan Beranda: pilih bagian Beranda yang tampil, geser
/// urutannya, dan pilih jenis aktivitas pada Aktivitas terbaru. Pilihan ini
/// berlaku untuk usaha yang sedang dibuka; usaha lain punya pilihan sendiri.
class HomePrefsPage extends StatelessWidget {
  const HomePrefsPage({super.key, this.businessName});

  final String? businessName;

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
                        ? 'Berlaku untuk usaha yang sedang dibuka.'
                        : 'Berlaku untuk usaha "$businessName".',
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
                const SectionTitle('Urutan bagian'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    for (var i = 0; i < p.order.length; i++) ...[
                      if (i > 0) const Divider(),
                      _OrderTile(
                        title: homeSectionTitles[p.order[i]] ?? p.order[i],
                        shown: p.sectionShown(p.order[i]),
                        canUp: i > 0,
                        canDown: i < p.order.length - 1,
                        onUp: () =>
                            set(p.copyWith(order: _swap(p.order, i, i - 1))),
                        onDown: () =>
                            set(p.copyWith(order: _swap(p.order, i, i + 1))),
                      ),
                    ],
                  ]),
                ),
                const SectionTitle('Bagian Beranda'),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    toggle('Saldo kas', '', p.showBalance,
                        (v) => set(p.copyWith(showBalance: v))),
                    const Divider(),
                    toggle('Kas masuk dan keluar bulan ini', '', p.showFlow,
                        (v) => set(p.copyWith(showFlow: v))),
                    const Divider(),
                    toggle('Keuntungan bulan ini', '', p.showProfit,
                        (v) => set(p.copyWith(showProfit: v))),
                    const Divider(),
                    toggle('Tombol cepat', '', p.showQuickActions,
                        (v) => set(p.copyWith(showQuickActions: v))),
                    const Divider(),
                    toggle('Piutang dan utang belum lunas', '', p.showDebtCards,
                        (v) => set(p.copyWith(showDebtCards: v))),
                    const Divider(),
                    toggle('Aktivitas terbaru', '', p.showActivity,
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
                          '',
                          p.actCashIn,
                          p.showActivity
                              ? (v) => set(p.copyWith(actCashIn: v))
                              : null),
                      const Divider(),
                      toggle(
                          'Kas keluar',
                          '',
                          p.actCashOut,
                          p.showActivity
                              ? (v) => set(p.copyWith(actCashOut: v))
                              : null),
                      const Divider(),
                      toggle(
                          'Transaksi hutang',
                          '',
                          p.actCredit,
                          p.showActivity
                              ? (v) => set(p.copyWith(actCredit: v))
                              : null),
                      const Divider(),
                      toggle(
                          'Pelunasan dan pembayaran',
                          '',
                          p.actPayments,
                          p.showActivity
                              ? (v) => set(p.copyWith(actPayments: v))
                              : null),
                      const Divider(),
                      toggle(
                          'Pemberian dan penerimaan utang',
                          '',
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
                      const SizedBox(height: 12),
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

List<String> _swap(List<String> list, int a, int b) {
  final next = [...list];
  final tmp = next[a];
  next[a] = next[b];
  next[b] = tmp;
  return next;
}

/// Satu baris urutan: nama bagian, penanda bila dimatikan, dan panah geser.
class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.title,
    required this.shown,
    required this.canUp,
    required this.canDown,
    required this.onUp,
    required this.onDown,
  });

  final String title;
  final bool shown;
  final bool canUp;
  final bool canDown;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600, color: shown ? null : muted)),
            if (!shown)
              Text('Dimatikan',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ]),
        ),
        IconButton(
          tooltip: 'Naikkan',
          onPressed: canUp ? onUp : null,
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
        IconButton(
          tooltip: 'Turunkan',
          onPressed: canDown ? onDown : null,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
      ]),
    );
  }
}
