// Galeri gaya tampilan untuk diperiksa di peramban tanpa login:
//   flutter build web -t tool/style_gallery.dart
// Bukan bagian aplikasi.
import 'package:flutter/material.dart';
import 'package:rekap_rapi/common/floating_nav_bar.dart';
import 'package:rekap_rapi/common/widgets.dart';
import 'package:rekap_rapi/theme/app_style.dart';
import 'package:rekap_rapi/theme/app_theme.dart';
import 'package:rekap_rapi/theme/background_controller.dart';
import 'package:rekap_rapi/theme/style_picker_page.dart';

void main() => runApp(const _Gallery());

class _Gallery extends StatefulWidget {
  const _Gallery();

  @override
  State<_Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<_Gallery> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: styleController,
      builder: (context, _) {
        final style = styleController.style;
        final theme = buildTheme(_dark ? Brightness.dark : Brightness.light,
            'Plus Jakarta Sans', Brand.seed, style);
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: Builder(builder: (context) {
            final t = Theme.of(context);
            final g =
                backgroundGradient(t.brightness, t.scaffoldBackgroundColor);
            return DecoratedBox(
              decoration:
                  BoxDecoration(color: t.scaffoldBackgroundColor, gradient: g),
              child: Scaffold(
                backgroundColor: Colors.transparent,
                extendBody: true,
                appBar: AppBar(
                  backgroundColor: Colors.transparent,
                  title: Text('Gaya: ${style.label}'),
                  actions: [
                    IconButton(
                        onPressed: () => setState(() => _dark = !_dark),
                        icon: Icon(_dark ? Icons.light_mode : Icons.dark_mode)),
                    IconButton(
                        onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => const StylePickerPage())),
                        icon: const Icon(Icons.style)),
                  ],
                ),
                body: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  children: [
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final s in AppStyle.values)
                        ChoiceChip(
                          label: Text(s.label),
                          selected: s == style,
                          onSelected: (_) => styleController.set(s),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    StyledBox(
                      padding: const EdgeInsets.all(22),
                      tint: Brand.profit,
                      child: Text('Laba  Rp 1.250.000',
                          style: t.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: Brand.profit)),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      for (final (l, v, c) in [
                        ('Pemasukan', 'Rp 3.400.000', Brand.income),
                        ('Pengeluaran', 'Rp 2.150.000', Brand.expense),
                      ]) ...[
                        Expanded(
                          child: StyledBox(
                            tint: c,
                            padding: const EdgeInsets.all(14),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  IconBadge(Icons.south_west_rounded,
                                      color: c, size: 32),
                                  const SizedBox(height: 12),
                                  Text(l, style: t.textTheme.labelMedium),
                                  Text(v,
                                      style: t.textTheme.titleMedium?.copyWith(
                                          color: c,
                                          fontWeight: FontWeight.w700)),
                                ]),
                          ),
                        ),
                        if (l == 'Pemasukan') const SizedBox(width: 12),
                      ],
                    ]),
                    const SectionTitle('Transaksi'),
                    SoftCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (final (title, amount, inc) in [
                          ('Penjualan', '+Rp 50.000', true),
                          ('Listrik & Air', '-Rp 320.000', false),
                          ('Penjualan', '+Rp 125.000', true),
                        ])
                          EntryRow(
                            icon: inc
                                ? Icons.storefront_rounded
                                : Icons.bolt_rounded,
                            iconColor: inc ? Brand.income : Brand.expense,
                            title: title,
                            amount: amount,
                            amountColor: inc ? Brand.income : Brand.expense,
                            sub: '14:20',
                            note: inc ? 'kopi susu' : null,
                          ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    const TextField(
                        decoration: InputDecoration(labelText: 'Catatan')),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: () {}, child: const Text('Simpan')),
                    const SizedBox(height: 8),
                    OutlinedButton(
                        onPressed: () {}, child: const Text('Batal')),
                  ],
                ),
                bottomNavigationBar: FloatingNavBar(
                  items: const [
                    FloatingNavItem(Icons.bar_chart_outlined,
                        Icons.bar_chart_rounded, 'Rekapan'),
                    FloatingNavItem(Icons.receipt_long_outlined,
                        Icons.receipt_long_rounded, 'Transaksi'),
                    FloatingNavItem(Icons.handshake_outlined,
                        Icons.handshake_rounded, 'Utang'),
                    FloatingNavItem(Icons.person_outline_rounded,
                        Icons.person_rounded, 'Profil'),
                  ],
                  selectedIndex: 0,
                  onSelected: (_) {},
                  onCenter: () {},
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
