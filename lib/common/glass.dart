import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Efek kaca: isi di belakang dikaburkan, lalu ditutup warna latar yang cukup
/// pekat. Kaburnya memberi kesan kaca; pekatnya menjaga tulisan tetap terbaca
/// di atas kartu dan angka berwarna yang lewat di belakangnya.
///
/// Kepekatan sengaja tinggi (bilah 0,80, lembar 0,92). Jangan diturunkan tanpa
/// memeriksa tulisan di atas kartu hijau dan kartu keuntungan.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.opacity = 0.8,
    this.sigma = 24,
    this.border,
    this.radius,
  });

  final Widget child;

  /// Kepekatan warna latar (0 sampai 1).
  final double opacity;

  /// Tingkat kabur.
  final double sigma;
  final Border? border;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fill = theme.scaffoldBackgroundColor.withValues(alpha: opacity);
    final body = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: DecoratedBox(
        decoration: BoxDecoration(color: fill, border: border),
        child: child,
      ),
    );
    return radius == null
        ? ClipRect(child: body)
        : ClipRRect(borderRadius: radius!, child: body);
  }
}

Color _hairline(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.10);

/// Bilah atas (di `flexibleSpace` AppBar) atau bilah bawah dengan efek kaca.
/// [top] true untuk bilah atas: garis tipis di sisi bawahnya; false untuk bilah
/// bawah: garis tipis di sisi atasnya.
class GlassBar extends StatelessWidget {
  const GlassBar({super.key, this.child, this.top = false});

  final Widget? child;
  final bool top;

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(color: _hairline(context));
    return GlassSurface(
      opacity: 0.8,
      border: top ? Border(bottom: line) : Border(top: line),
      child: child ?? const SizedBox.expand(),
    );
  }
}

/// Seperti `showModalBottomSheet`, tetapi lembarnya berefek kaca dan latar
/// belakangnya digelapkan agar lembar mudah dibaca. Pegangan geser digambar
/// sendiri di dalam kaca, jadi `showDragHandle` tidak dipakai.
Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  // Diterima agar bisa menggantikan `showModalBottomSheet` apa adanya.
  bool showDragHandle = true,
  BoxConstraints? constraints,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    constraints: constraints,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (sheetContext) => GlassSheet(child: Builder(builder: builder)),
  );
}

/// Isi lembar kaca: sudut atas membulat, pegangan geser, dan garis tipis di tepi.
class GlassSheet extends StatelessWidget {
  const GlassSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSurface(
      opacity: 0.92,
      sigma: 28,
      radius: const BorderRadius.vertical(top: Radius.circular(28)),
      border: Border(top: BorderSide(color: _hairline(context))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Flexible(child: child),
      ]),
    );
  }
}
