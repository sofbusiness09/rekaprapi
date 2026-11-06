import 'package:flutter/material.dart';

import 'background_controller.dart';

/// Lembar pengaturan latar gradasi: hidup atau mati, dan pilihan warna.
Future<void> showBackgroundPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 480),
    builder: (_) => const _BackgroundSheet(),
  );
}

class _BackgroundSheet extends StatelessWidget {
  const _BackgroundSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: ListenableBuilder(
        listenable: backgroundController,
        builder: (context, _) {
          final on = backgroundController.enabled;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Latar gradasi',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktifkan'),
                value: on,
                onChanged: backgroundController.setEnabled,
              ),
              const SizedBox(height: 4),
              Opacity(
                opacity: on ? 1 : 0.4,
                child: Wrap(spacing: 14, runSpacing: 14, children: [
                  for (final p in backgroundPresets)
                    _Swatch(
                      preset: p,
                      selected: backgroundController.preset.id == p.id,
                      onTap:
                          on ? () => backgroundController.setPreset(p) : null,
                      ring: scheme.primary,
                    ),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.preset,
    required this.selected,
    required this.onTap,
    required this.ring,
  });

  final BackgroundPreset preset;
  final bool selected;
  final VoidCallback? onTap;
  final Color ring;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final base = Theme.of(context).scaffoldBackgroundColor;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 56,
          height: 72,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [preset.tint(b), base],
            ),
            border: Border.all(
                color: selected ? ring : Colors.black.withValues(alpha: 0.12),
                width: selected ? 2.4 : 1),
          ),
          child: selected
              ? Icon(Icons.check_rounded, color: ring)
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 6),
        Text(preset.name, style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }
}
