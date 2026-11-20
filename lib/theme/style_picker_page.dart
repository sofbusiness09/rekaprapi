import 'package:flutter/material.dart';

import '../common/widgets.dart';
import 'app_style.dart';
import 'app_theme.dart';
import 'background_controller.dart';
import 'font_controller.dart';

/// Pengaturan > Gaya tampilan: pilih gaya dengan melihat pratinjaunya.
class StylePickerPage extends StatelessWidget {
  const StylePickerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gaya tampilan')),
      body: ListenableBuilder(
        listenable: styleController,
        builder: (context, _) => ContentWidth(
          maxWidth: 900,
          child: LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth >= 640 ? 2 : 1;
            return GridView.count(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              crossAxisCount: cols,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: cols == 2 ? 1.55 : 1.75,
              children: [
                for (final s in AppStyle.values)
                  StylePreview(
                    style: s,
                    selected: styleController.style == s,
                    onTap: () => styleController.set(s),
                  ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// Pratinjau satu gaya: latar, kartu angka, dan tombol, digambar dengan tema gaya itu.
class StylePreview extends StatelessWidget {
  const StylePreview({
    super.key,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final AppStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outer = Theme.of(context);
    final theme = buildTheme(outer.brightness, fontController.font.family,
        backgroundController.preset.accent, style);
    final gradient = backgroundGradient(
        theme.brightness, theme.scaffoldBackgroundColor,
        style: style);
    return Semantics(
      button: true,
      selected: selected,
      label: style.label,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected ? outer.colorScheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
          padding: const EdgeInsets.all(3),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Theme(
              data: theme,
              child: Builder(builder: (context) {
                final t = Theme.of(context);
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.scaffoldBackgroundColor,
                    gradient: gradient,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text(style.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: t.colorScheme.onSurface)),
                          ),
                          if (selected)
                            Icon(Icons.check_circle_rounded,
                                color: t.colorScheme.primary),
                        ]),
                        Text(style.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.textTheme.bodySmall?.copyWith(
                                color: t.colorScheme.onSurfaceVariant)),
                        const Spacer(),
                        const Row(children: [
                          Expanded(
                            child: StyledBox(
                              tint: Brand.income,
                              padding: EdgeInsets.all(10),
                              child: _Sample(
                                  'Pemasukan', 'Rp 1,2 jt', Brand.income),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: StyledBox(
                              tint: Brand.expense,
                              padding: EdgeInsets.all(10),
                              child: _Sample(
                                  'Pengeluaran', 'Rp 450 rb', Brand.expense),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 34,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(34),
                                padding: EdgeInsets.zero),
                            onPressed: onTap,
                            child:
                                Text(selected ? 'Dipakai' : 'Pakai gaya ini'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _Sample extends StatelessWidget {
  const _Sample(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          maxLines: 1,
          style: t.textTheme.labelSmall
              ?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(value,
            style: t.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: color)),
      ),
    ]);
  }
}
