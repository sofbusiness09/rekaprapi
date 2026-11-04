import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'font_controller.dart';
import '../common/glass.dart';

/// Lembar pilihan jenis huruf, tiap pilihan tampil dengan hurufnya sendiri.
Future<void> showFontPicker(BuildContext context) {
  return showGlassSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (_) => const _FontSheet(),
  );
}

class _FontSheet extends StatelessWidget {
  const _FontSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SafeArea(
      child: ListenableBuilder(
        listenable: fontController,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Jenis huruf',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                    'Berlaku di seluruh aplikasi dan tersimpan di perangkat ini. Huruf diunduh sekali, jadi butuh internet saat pertama dipakai.',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ),
            ),
            for (final f in appFonts)
              _FontTile(
                font: f,
                selected: fontController.font.id == f.id,
                onTap: () => fontController.set(f),
              ),
          ]),
        ),
      ),
    );
  }
}

class _FontTile extends StatelessWidget {
  const _FontTile(
      {required this.font, required this.selected, required this.onTap});

  final AppFont font;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sample = GoogleFonts.getFont(font.family,
        textStyle: theme.textTheme.titleMedium,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface);
    final small = GoogleFonts.getFont(font.family,
        textStyle: theme.textTheme.bodyMedium,
        fontWeight: FontWeight.w500,
        color: scheme.onSurfaceVariant);
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      selected: selected,
      selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
      title: Text(font.name, style: sample),
      subtitle: Text('${font.note}\nRp 1.250.000  ·  Penjualan hari ini',
          style: small),
      isThreeLine: true,
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: scheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
