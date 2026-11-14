import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Membatasi lebar isi agar tidak melebar di layar lebar.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 960});

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
                    ?.copyWith(fontWeight: FontWeight.w600)),
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
                ?.copyWith(fontWeight: FontWeight.w600)),
        if (subtitle != null) ...[
          const SizedBox(height: 8),
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
  const InitialAvatar(this.name,
      {super.key, this.color, this.size = 44, this.photoUrl});

  final String name;
  final Color? color;
  final double size;

  /// Foto pengganti inisial; bila gagal dimuat, inisial tetap tampil.
  final String? photoUrl;

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
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(initials,
          style: TextStyle(
              color: c, fontWeight: FontWeight.w600, fontSize: size * 0.34)),
    );
    final url = photoUrl;
    if (url == null || url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // Foto kecil; dimuat pada ukuran tampil agar hemat memori.
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, __, ___) => fallback,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : fallback,
      ),
    );
  }
}

/// Kotak ikon: alas netral, hanya ikonnya yang memakai warna makna.
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
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(size * 0.3)),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

/// Teks yang mengecil sampai muat di ruangnya (paling kecil [minFontSize]),
/// baru dipotong dengan titik-titik. Dipakai untuk label di kartu sempit.
class FitText extends StatelessWidget {
  const FitText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.minFontSize = 10,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final int maxLines;
  final double minFontSize;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final base = DefaultTextStyle.of(context).style.merge(style);
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(builder: (context, c) {
      var size = base.fontSize ?? 14;
      if (c.maxWidth.isFinite) {
        while (size > minFontSize) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: base.copyWith(fontSize: size)),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: maxLines,
          )..layout(maxWidth: c.maxWidth);
          final fits = !painter.didExceedMaxLines;
          painter.dispose();
          if (fits) break;
          size -= 0.5;
        }
      }
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: base.copyWith(fontSize: size),
      );
    });
  }
}

/// Satu baris daftar seperti nota: judul dan nominal dihubungkan garis titik-titik.
class EntryRow extends StatelessWidget {
  const EntryRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.amount,
    required this.amountColor,
    this.sub,
    this.status,
    this.statusColor,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String amount;
  final Color amountColor;
  final String? sub;
  final String? status;
  final Color? statusColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final surface = theme.cardTheme.color ?? theme.colorScheme.surface;
    final dots = theme.colorScheme.onSurface.withValues(alpha: 0.28);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          IconBadge(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(alignment: Alignment.bottomCenter, children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 5,
                  height: 2,
                  child: CustomPaint(painter: _DotLine(dots)),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: ColoredBox(
                        color: surface,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    ColoredBox(
                      color: surface,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text(amount,
                            style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: amountColor)),
                      ),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(
                  child: Text(sub ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                ),
                if (status != null) ...[
                  const SizedBox(width: 8),
                  Text(status!,
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor, fontWeight: FontWeight.w600)),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _DotLine extends CustomPainter {
  const _DotLine(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var x = 0.0; x < size.width; x += 5) {
      canvas.drawCircle(Offset(x + 1, size.height / 2), 1, paint);
    }
  }

  @override
  bool shouldRepaint(_DotLine old) => old.color != color;
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
