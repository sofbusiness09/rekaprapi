import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Membatasi lebar isi agar tidak melebar di layar lebar.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 720});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      );
}

/// Kartu lembut dengan sudut membulat.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        color: color,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(children: [
          Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
              color: scheme.primaryContainer, shape: BoxShape.circle),
          child: Icon(icon, size: 40, color: scheme.onPrimaryContainer),
        ),
        const SizedBox(height: 20),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        if (actionLabel != null) ...[
          const SizedBox(height: 20),
          FilledButton.tonal(
            onPressed: onAction,
            style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
            child: Text(actionLabel!),
          ),
        ],
      ]),
    );
  }
}

/// Lingkaran berisi inisial nama.
class InitialAvatar extends StatelessWidget {
  const InitialAvatar(this.name, {super.key, this.color, this.size = 44});

  final String name;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.length == 1
                ? parts.first.substring(0, 1)
                : parts.first.substring(0, 1) + parts.last.substring(0, 1))
            .toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(size * 0.34)),
      child: Text(initials,
          style: TextStyle(
              color: c, fontWeight: FontWeight.w800, fontSize: size * 0.34)),
    );
  }
}

/// Kotak ikon berwarna (ikon kategori / jenis transaksi).
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, required this.color, this.size = 44});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(size * 0.34)),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

/// Ikon kategori berdasarkan nama; cadangan mengikuti jenis.
IconData categoryIcon(String? name, {required bool income}) {
  final n = (name ?? '').toLowerCase();
  if (n.contains('piutang')) return Icons.north_east_rounded;
  if (n.contains('utang')) return Icons.south_west_rounded;
  if (n.contains('jual')) return Icons.storefront_rounded;
  if (n.contains('gaji')) return Icons.badge_rounded;
  if (n.contains('sewa')) return Icons.home_work_rounded;
  if (n.contains('listrik') || n.contains('air')) return Icons.bolt_rounded;
  if (n.contains('transport')) return Icons.local_shipping_rounded;
  if (n.contains('stok') || n.contains('beli'))
    return Icons.inventory_2_rounded;
  return income ? Icons.south_west_rounded : Icons.north_east_rounded;
}

Color amountColor(bool income) => income ? Brand.income : Brand.expense;
