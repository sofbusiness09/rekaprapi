import 'package:flutter/material.dart';

import 'theme_controller.dart';
import 'package:rekap_rapi/l10n/l10n.dart';

/// Pemilih tampilan Terang / Gelap / Ikuti perangkat.
/// [compact] hanya menampilkan ikon (untuk sidebar yang sempit).
class ThemeModePicker extends StatelessWidget {
  const ThemeModePicker({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          style: compact
              ? const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 8)),
                )
              : null,
          segments: [
            ButtonSegment(
              value: ThemeMode.light,
              icon: const Icon(Icons.light_mode_rounded, size: 18),
              label: compact ? null : _OneLine(tr('Terang')),
              tooltip: tr('Terang'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: const Icon(Icons.dark_mode_rounded, size: 18),
              label: compact ? null : _OneLine(tr('Gelap')),
              tooltip: tr('Gelap'),
            ),
            ButtonSegment(
              value: ThemeMode.system,
              icon: const Icon(Icons.brightness_auto_rounded, size: 18),
              label: compact ? null : _OneLine(tr('Otomatis')),
              tooltip: tr('Ikuti perangkat'),
            ),
          ],
          selected: {themeController.mode},
          onSelectionChanged: (s) => themeController.set(s.first),
        );
      },
    );
  }
}

/// Pilihan tema berupa tiga ikon tersusun atas-bawah (terang, gelap, ikuti perangkat),
/// untuk bilah samping yang sempit.
class ThemeModeColumn extends StatelessWidget {
  const ThemeModeColumn({super.key});

  @override
  Widget build(BuildContext context) {
    final modes = <(ThemeMode, IconData, String)>[
      (ThemeMode.light, Icons.light_mode_rounded, tr('Terang')),
      (ThemeMode.dark, Icons.dark_mode_rounded, tr('Gelap')),
      (ThemeMode.system, Icons.brightness_auto_rounded, tr('Ikuti perangkat')),
    ];
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) =>
          Column(mainAxisSize: MainAxisSize.min, children: [
        for (final m in modes)
          IconButton(
            tooltip: m.$3,
            isSelected: themeController.mode == m.$1,
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: Icon(m.$2),
            style: themeController.mode == m.$1
                ? IconButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.secondaryContainer)
                : null,
            onPressed: () => themeController.set(m.$1),
          ),
      ]),
    );
  }
}

/// Tulisan pilihan yang tidak pernah pindah baris (mis. "Otomatis" tidak terpotong).
class _OneLine extends StatelessWidget {
  const _OneLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(text, maxLines: 1, softWrap: false),
      );
}

/// Tombol cepat di bilah atas: berpindah antara terang dan gelap. "Ikuti perangkat"
/// tetap dipilih dari Pengaturan. Disembunyikan untuk gaya yang selalu gelap.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? tr('Mode terang') : tr('Mode gelap'),
      onPressed: () =>
          themeController.set(dark ? ThemeMode.light : ThemeMode.dark),
      icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
    );
  }
}
