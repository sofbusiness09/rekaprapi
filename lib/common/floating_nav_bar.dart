import 'package:flutter/material.dart';

import '../theme/app_style.dart';

/// Satu tombol di bilah navigasi melayang.
class FloatingNavItem {
  const FloatingNavItem(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// Bilah navigasi bawah berbentuk kapsul yang melayang di atas dasar layar.
/// Setiap tab menampilkan ikon dengan namanya di bawah; tab terpilih berwarna aksen.
/// Bila [onCenter] diisi, tombol bulat "+" berada di tengah deretan tab.
class FloatingNavBar extends StatelessWidget {
  const FloatingNavBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.onCenter,
    this.centerTooltip = 'Catat',
  });

  final List<FloatingNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback? onCenter;
  final String centerTooltip;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        // Kapsul mengikuti gaya tampilan (kaca, timbul, brutal, neon, ...).
        child: StyledBox(
          radius: tokens.style == AppStyle.brutal ? 14 : 32,
          decoration: tokens.style == AppStyle.standard
              ? _standardDecoration(context)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(children: [
              for (var i = 0; i < items.length; i++) ...[
                if (onCenter != null && i == (items.length + 1) ~/ 2)
                  _CenterButton(onTap: onCenter!, tooltip: centerTooltip),
                // Lebar sama rata; nama selalu tampil di bawah ikon.
                Expanded(
                  child: _NavButton(
                    item: items[i],
                    selected: i == selectedIndex,
                    onTap: () => onSelected(i),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  /// Gaya bawaan: kapsul putih dengan bayangan lembut seperti sebelumnya.
  BoxDecoration _standardDecoration(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return BoxDecoration(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(32),
      border: Border.all(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.10)),
      boxShadow: dark
          ? const []
          : [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 4)),
            ],
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton(
      {required this.item, required this.selected, required this.onTap});

  final FloatingNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 56,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            // Kapsul lembut warna aksen di belakang tab terpilih.
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? item.selectedIcon : item.icon,
                  size: 22, color: color),
              const SizedBox(height: 3),
              // Nama mengecil sendiri di layar sempit agar tetap satu baris utuh.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(item.label,
                    maxLines: 1,
                    style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 11.5,
                        height: 1.1,
                        color: color,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tombol "+" bulat di tengah panel bawah.
class _CenterButton extends StatelessWidget {
  const _CenterButton({required this.onTap, required this.tooltip});

  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: scheme.primary,
          shape: const CircleBorder(),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(Icons.add_rounded, size: 28, color: scheme.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
