import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_style.dart';

/// Warna merek dan warna makna (masuk/keluar/piutang/utang).
class Brand {
  static const seed = Color(0xFF0E9F6E);
  static const deep = Color(0xFF065F46);
  static const income = Color(0xFF12A150);
  static const expense = Color(0xFFE5484D);

  /// Piutang (kontak berutang kepada Anda): merah.
  static const receivable = Color(0xFFDC2626);

  /// Utang (Anda berutang kepada kontak): biru.
  static const payable = Color(0xFF2F7DE1);

  /// Status belum lunas / menunggu: oranye.
  static const pending = Color(0xFFF08A24);

  /// Aksen biru netral (undangan, kode, tombol cepat).
  static const info = Color(0xFF2F7DE1);
  static const profit = Color(0xFF0B7A55);
}

/// Huruf reguler terlihat tipis di layar ponsel; teks isi dan label dinaikkan
/// satu tingkat ketebalan agar lebih terbaca.
TextTheme _firmer(TextTheme t, String family) {
  // Angka tabular agar nominal rupiah di daftar dan laporan sejajar.
  const figures = [FontFeature.tabularFigures()];
  TextStyle? weigh(TextStyle? s, FontWeight w) => s == null
      ? null
      : GoogleFonts.getFont(family,
          textStyle: s, fontWeight: w, fontFeatures: figures);
  TextStyle? same(TextStyle? s) => s == null
      ? null
      : GoogleFonts.getFont(family, textStyle: s, fontFeatures: figures);
  return t.copyWith(
    displayLarge: same(t.displayLarge),
    displayMedium: same(t.displayMedium),
    displaySmall: same(t.displaySmall),
    headlineLarge: same(t.headlineLarge),
    headlineMedium: same(t.headlineMedium),
    headlineSmall: same(t.headlineSmall),
    titleLarge: same(t.titleLarge),
    titleMedium: same(t.titleMedium),
    titleSmall: same(t.titleSmall),
    bodyLarge: weigh(t.bodyLarge, FontWeight.w500),
    bodyMedium: weigh(t.bodyMedium, FontWeight.w500),
    bodySmall: weigh(t.bodySmall, FontWeight.w500),
    labelLarge: weigh(t.labelLarge, FontWeight.w600),
    labelMedium: weigh(t.labelMedium, FontWeight.w600),
    labelSmall: weigh(t.labelSmall, FontWeight.w600),
  );
}

/// Warna keuntungan: hijau tua di tema terang, hijau terang di tema gelap, agar
/// angka dan tulisannya mudah terbaca di atas kotak berwarna.
Color profitColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF4ADE9F)
        : Brand.profit;

ThemeData buildTheme(Brightness brightness,
    [String fontFamily = 'Plus Jakarta Sans',
    Color seed = Brand.seed,
    AppStyle style = AppStyle.standard]) {
  // Cyberpunk selalu gelap dengan palet neon sendiri.
  if (style.forcesDark) brightness = Brightness.dark;
  final light = brightness == Brightness.light;
  final cyber = style == AppStyle.cyber;
  var scheme = ColorScheme.fromSeed(
      seedColor: cyber ? Neon.cyan : seed, brightness: brightness);
  if (cyber) {
    scheme = scheme.copyWith(
      primary: Neon.cyan,
      onPrimary: const Color(0xFF001318),
      secondary: Neon.magenta,
      tertiary: Neon.magenta,
      surface: Neon.surface,
      onSurface: const Color(0xFFEAF9FF),
      onSurfaceVariant: const Color(0xFF9BB7C9),
    );
  }
  final base = ThemeData(
      colorScheme: scheme, useMaterial3: true, brightness: brightness);
  final text =
      _firmer(GoogleFonts.getTextTheme(fontFamily, base.textTheme), fontFamily);
  final tokens = StyleTokens.forStyle(style, brightness);

  // Permukaan netral; warna merek hanya muncul di aksen dan angka.
  final (Color bg, Color surface, Color outline) = switch (style) {
    AppStyle.standard => light
        ? (const Color(0xFFF5F6F5), Colors.white, const Color(0xFFE5E7E5))
        : (
            const Color(0xFF101211),
            const Color(0xFF1A1C1B),
            const Color(0xFF2B2E2C)
          ),
    AppStyle.glass => light
        ? (const Color(0xFFEEF2F8), Colors.white, const Color(0xFFDCE3EE))
        : (
            const Color(0xFF0E1016),
            const Color(0xFF1A1D26),
            const Color(0xFF2C3140)
          ),
    AppStyle.minimal => light
        ? (Colors.white, Colors.white, const Color(0xFFE9E9EB))
        : (
            const Color(0xFF0B0B0C),
            const Color(0xFF0B0B0C),
            const Color(0xFF26262A)
          ),
    AppStyle.neumorph => light
        ? (tokens.cardColor, tokens.cardColor, const Color(0xFFCBD3DE))
        : (tokens.cardColor, tokens.cardColor, const Color(0xFF363B43)),
    AppStyle.brutal => light
        ? (const Color(0xFFFFF4D6), Colors.white, const Color(0xFF111111))
        : (
            const Color(0xFF161616),
            const Color(0xFF242424),
            const Color(0xFFF2F2F2)
          ),
    AppStyle.cyber => (Neon.bg, Neon.surface, Neon.cyan.withValues(alpha: 0.4)),
  };
  final brutal = style == AppStyle.brutal;
  final r = switch (style) {
    AppStyle.brutal => 8.0,
    AppStyle.minimal => 10.0,
    AppStyle.cyber => 10.0,
    _ => 14.0,
  };
  final inputFill = style == AppStyle.glass
      ? (light
          ? Colors.white.withValues(alpha: 0.6)
          : Colors.white.withValues(alpha: 0.06))
      : surface;

  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide(color: c, width: brutal ? 2 : w),
      );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(r),
    side: brutal ? BorderSide(color: outline, width: 2) : BorderSide.none,
  );

  return base.copyWith(
    scaffoldBackgroundColor: bg,
    textTheme: text,
    extensions: [tokens],
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge
          ?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurface),
    ),
    cardTheme: CardThemeData(
      color: tokens.cardColor,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius),
        side: tokens.border ?? BorderSide.none,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(outline),
      enabledBorder: border(outline),
      focusedBorder: border(scheme.primary, 1.6),
      errorBorder: border(scheme.error),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: buttonShape,
        textStyle: text.labelLarge
            ?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
        side: BorderSide(color: outline, width: brutal ? 2 : 1),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r - 4)),
      side: BorderSide(color: outline, width: brutal ? 2 : 1),
      backgroundColor: style == AppStyle.glass ? inputFill : surface,
      labelStyle: text.labelLarge,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primaryContainer,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: surface,
      indicatorColor: scheme.primaryContainer,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(brutal ? 12 : 28)),
          side: brutal
              ? BorderSide(color: outline, width: 2.5)
              : BorderSide.none),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(brutal ? 10 : 28),
          side: brutal
              ? BorderSide(color: outline, width: 2.5)
              : BorderSide.none),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(r)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(brutal ? 8 : 20),
          side:
              brutal ? BorderSide(color: outline, width: 2) : BorderSide.none),
    ),
    dividerTheme: DividerThemeData(
        color: outline.withValues(alpha: brutal ? 0.35 : 1), space: 1),
  );
}
