import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rekap_rapi/l10n/l10n.dart';

/// Gaya tampilan aplikasi. Disimpan per perangkat.
enum AppStyle {
  standard('Bawaan', 'Lembut dan rapi, seperti biasa'),
  glass('Glassmorphism', 'Kartu kaca buram di atas latar warna-warni'),
  minimal('Minimalism', 'Polos, tanpa bayangan, banyak ruang kosong'),
  neumorph('Neumorphism', 'Kartu timbul dari latar, bayangan lembut'),
  brutal('Neo-Brutalism', 'Bingkai hitam tebal, bayangan keras, warna cerah'),
  cyber('Cyberpunk neon', 'Gelap pekat dengan cahaya neon');

  const AppStyle(this.label, this.description);

  final String label;
  final String description;

  /// Nama dan keterangan dalam bahasa aktif.
  String get title => tr(label);
  String get info => tr(description);

  static AppStyle parse(String? v) =>
      AppStyle.values.firstWhere((s) => s.name == v, orElse: () => standard);

  /// Cyberpunk selalu gelap.
  bool get forcesDark => this == cyber;
}

class StyleController extends ChangeNotifier {
  static const _key = 'app_style';

  AppStyle _style = AppStyle.standard;
  AppStyle get style => _style;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _style = AppStyle.parse(prefs.getString(_key));
    } catch (_) {
      // Penyimpanan tidak tersedia: gaya bawaan.
    }
    notifyListeners();
  }

  Future<void> set(AppStyle style) async {
    if (_style == style) return;
    _style = style;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, style.name);
    } catch (_) {
      // Tetap berlaku selama aplikasi terbuka walau gagal disimpan.
    }
  }
}

final styleController = StyleController();

/// Warna neon gaya Cyberpunk.
class Neon {
  static const cyan = Color(0xFF00E5FF);
  static const magenta = Color(0xFFFF2BD6);
  static const bg = Color(0xFF07040F);
  static const surface = Color(0xFF120B24);
}

/// Ukuran dan hiasan kartu per gaya, dipakai SoftCard, panel bawah, dan kartu angka.
@immutable
class StyleTokens extends ThemeExtension<StyleTokens> {
  const StyleTokens({
    required this.style,
    required this.cardColor,
    required this.radius,
    required this.shadows,
    this.border,
    this.blur = 0,
  });

  final AppStyle style;
  final Color cardColor;
  final double radius;
  final List<BoxShadow> shadows;
  final BorderSide? border;

  /// Kekuatan buram kaca di belakang kartu (Glassmorphism); 0 = tanpa buram.
  final double blur;

  static StyleTokens of(BuildContext context) =>
      Theme.of(context).extension<StyleTokens>() ??
      StyleTokens.forStyle(AppStyle.standard, Theme.of(context).brightness);

  factory StyleTokens.forStyle(AppStyle style, Brightness b) {
    final light = b == Brightness.light;
    switch (style) {
      case AppStyle.standard:
        return StyleTokens(
          style: style,
          cardColor: light ? Colors.white : const Color(0xFF1A1C1B),
          radius: 20,
          shadows: const [],
          border: BorderSide(
              color: light ? const Color(0xFFE5E7E5) : const Color(0xFF2B2E2C)),
        );
      case AppStyle.glass:
        return StyleTokens(
          style: style,
          cardColor: light
              ? Colors.white.withValues(alpha: 0.42)
              : Colors.white.withValues(alpha: 0.08),
          radius: 22,
          blur: 18,
          shadows: [
            BoxShadow(
                color: Colors.black.withValues(alpha: light ? 0.06 : 0.25),
                blurRadius: 24,
                offset: const Offset(0, 8)),
          ],
          border: BorderSide(
              color: Colors.white.withValues(alpha: light ? 0.7 : 0.16),
              width: 1.2),
        );
      case AppStyle.minimal:
        return StyleTokens(
          style: style,
          cardColor: light ? Colors.white : const Color(0xFF0B0B0C),
          radius: 12,
          shadows: const [],
          border: BorderSide(
              color: light ? const Color(0xFFE9E9EB) : const Color(0xFF26262A)),
        );
      case AppStyle.neumorph:
        return StyleTokens(
          style: style,
          cardColor: light ? const Color(0xFFE6EBF1) : const Color(0xFF262A30),
          radius: 22,
          shadows: light
              ? const [
                  BoxShadow(
                      color: Color(0xFFFFFFFF),
                      offset: Offset(-6, -6),
                      blurRadius: 14),
                  BoxShadow(
                      color: Color(0xFFB4BFCE),
                      offset: Offset(6, 6),
                      blurRadius: 14),
                ]
              : const [
                  BoxShadow(
                      color: Color(0xFF31363D),
                      offset: Offset(-5, -5),
                      blurRadius: 12),
                  BoxShadow(
                      color: Color(0xFF17191D),
                      offset: Offset(6, 6),
                      blurRadius: 12),
                ],
        );
      case AppStyle.brutal:
        final ink = light ? const Color(0xFF111111) : const Color(0xFFF2F2F2);
        return StyleTokens(
          style: style,
          cardColor: light ? Colors.white : const Color(0xFF242424),
          radius: 8,
          shadows: [BoxShadow(color: ink, offset: const Offset(4, 4))],
          border: BorderSide(color: ink, width: 2.5),
        );
      case AppStyle.cyber:
        return StyleTokens(
          style: style,
          cardColor: Neon.surface.withValues(alpha: 0.92),
          radius: 14,
          shadows: [
            BoxShadow(
                color: Neon.cyan.withValues(alpha: 0.22),
                blurRadius: 16,
                spreadRadius: 0.5),
          ],
          border:
              BorderSide(color: Neon.cyan.withValues(alpha: 0.65), width: 1.2),
        );
    }
  }

  /// Hiasan kartu; [tint] memberi nuansa warna (mis. kartu Pemasukan hijau).
  BoxDecoration card({Color? tint, double? radius}) {
    var color = cardColor;
    var side = border;
    if (tint != null) {
      switch (style) {
        case AppStyle.standard:
        case AppStyle.minimal:
          color = Color.alphaBlend(tint.withValues(alpha: 0.09), cardColor);
          side = BorderSide(color: tint.withValues(alpha: 0.2));
        case AppStyle.glass:
          color = Color.alphaBlend(tint.withValues(alpha: 0.12), cardColor);
        case AppStyle.cyber:
          side = BorderSide(color: tint.withValues(alpha: 0.75), width: 1.2);
        case AppStyle.neumorph:
        case AppStyle.brutal:
          break;
      }
    }
    final glow = style == AppStyle.cyber && tint != null
        ? [BoxShadow(color: tint.withValues(alpha: 0.25), blurRadius: 16)]
        : shadows;
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius ?? this.radius),
      border: side == null ? null : Border.fromBorderSide(side),
      boxShadow: glow,
    );
  }

  @override
  StyleTokens copyWith({AppStyle? style}) => this;

  @override
  StyleTokens lerp(ThemeExtension<StyleTokens>? other, double t) {
    if (other is! StyleTokens) return this;
    return StyleTokens(
      style: t < 0.5 ? style : other.style,
      cardColor: Color.lerp(cardColor, other.cardColor, t)!,
      radius: lerpDouble(radius, other.radius, t)!,
      shadows: t < 0.5 ? shadows : other.shadows,
      border: t < 0.5 ? border : other.border,
      blur: lerpDouble(blur, other.blur, t)!,
    );
  }
}

/// Kotak berhias sesuai gaya aktif. Untuk Glassmorphism, isi di belakangnya dibuat
/// buram (kaca). Dipakai SoftCard, panel bawah, dan kartu angka.
class StyledBox extends StatelessWidget {
  const StyledBox({
    super.key,
    required this.child,
    this.tint,
    this.radius,
    this.onTap,
    this.padding = EdgeInsets.zero,
    this.decoration,
  });

  final Widget child;
  final Color? tint;
  final double? radius;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  /// Hiasan khusus menggantikan hiasan gaya (mis. kartu Laba bergradasi).
  final BoxDecoration? decoration;

  @override
  Widget build(BuildContext context) {
    final tokens = StyleTokens.of(context);
    final r = BorderRadius.circular(radius ?? tokens.radius);
    final deco = decoration ?? tokens.card(tint: tint, radius: radius);
    Widget body = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: r,
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (tokens.blur > 0 && decoration == null) {
      // Kaca: bayangan di luar, buram dan isi di dalam bingkai.
      return DecoratedBox(
        decoration: BoxDecoration(borderRadius: r, boxShadow: deco.boxShadow),
        child: ClipRRect(
          borderRadius: r,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: tokens.blur, sigmaY: tokens.blur),
            child: DecoratedBox(
              decoration: deco.copyWith(boxShadow: const []),
              child: body,
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: deco,
      child: ClipRRect(borderRadius: r, child: body),
    );
  }
}
