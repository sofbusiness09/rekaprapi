import 'package:flutter/material.dart';

import '../common/widgets.dart';
import 'home_prefs.dart';
import 'package:rekap_rapi/l10n/l10n.dart';

/// Pengaturan > Tampilan Rekapan: grafik apa saja yang tampil di tab Rekapan.
/// Pilihan berlaku untuk pembukuan yang sedang dibuka.
class ReportPrefsPage extends StatelessWidget {
  const ReportPrefsPage({
    super.key,
    this.businessName,
    this.personal = false,
    this.canSeeProfit = true,
  });

  final String? businessName;

  /// Pembukuan Pribadi: tanpa grafik Laba.
  final bool personal;

  /// Staf tidak melihat grafik keuangan, hanya jatuh tempo utang piutang.
  final bool canSeeProfit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final charts = personal || canSeeProfit;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Tampilan Rekapan'))),
      body: ListenableBuilder(
        listenable: homePrefs,
        builder: (context, _) {
          final p = homePrefs.value;
          void set(HomePrefs next) => homePrefs.update(next);

          Widget toggle(IconData icon, String title, bool value,
                  ValueChanged<bool> onChanged) =>
              SwitchListTile(
                secondary: Icon(icon),
                title: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                value: value,
                onChanged: onChanged,
              );

          return ContentWidth(
            maxWidth: 640,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    businessName == null
                        ? tr('Berlaku untuk pembukuan yang sedang dibuka.')
                        : tr('Berlaku untuk pembukuan "{0}".', [businessName]),
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
                SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(children: [
                    if (charts) ...[
                      toggle(
                          Icons.bar_chart_rounded,
                          personal
                              ? tr('Arus kas')
                              : tr('Pemasukan dan pengeluaran'),
                          p.rpFlow,
                          (v) => set(p.copyWith(rpFlow: v))),
                      const Divider(),
                      if (!personal) ...[
                        toggle(Icons.show_chart_rounded, tr('Laba'), p.rpProfit,
                            (v) => set(p.copyWith(rpProfit: v))),
                        const Divider(),
                      ],
                      toggle(Icons.donut_large_rounded, tr('Per kategori'),
                          p.rpCategory, (v) => set(p.copyWith(rpCategory: v))),
                      const Divider(),
                      toggle(
                          Icons.calendar_month_rounded,
                          tr('Pengeluaran harian'),
                          p.rpCalendar,
                          (v) => set(p.copyWith(rpCalendar: v))),
                      const Divider(),
                    ],
                    toggle(Icons.event_rounded, tr('Jatuh tempo utang piutang'),
                        p.rpDue, (v) => set(p.copyWith(rpDue: v))),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                  child: Text(
                    tr('Kartu ringkasan di atas Rekapan selalu tampil.'),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
