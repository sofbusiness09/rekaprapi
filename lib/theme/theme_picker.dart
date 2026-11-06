import 'package:flutter/material.dart';

import 'theme_controller.dart';

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
              label: compact ? null : const Text('Terang'),
              tooltip: 'Terang',
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: const Icon(Icons.dark_mode_rounded, size: 18),
              label: compact ? null : const Text('Gelap'),
              tooltip: 'Gelap',
            ),
            ButtonSegment(
              value: ThemeMode.system,
              icon: const Icon(Icons.brightness_auto_rounded, size: 18),
              label: compact ? null : const Text('Otomatis'),
              tooltip: 'Ikuti perangkat',
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
    const modes = <(ThemeMode, IconData, String)>[
      (ThemeMode.light, Icons.light_mode_rounded, 'Terang'),
      (ThemeMode.dark, Icons.dark_mode_rounded, 'Gelap'),
      (ThemeMode.system, Icons.brightness_auto_rounded, 'Ikuti perangkat'),
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
