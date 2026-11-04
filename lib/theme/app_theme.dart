import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

/// Plus Jakarta Sans reguler terlihat tipis di layar ponsel; teks isi dan label
/// dinaikkan satu tingkat ketebalan agar lebih terbaca.
TextTheme _firmer(TextTheme t) {
  // Angka tabular agar nominal rupiah di daftar dan laporan sejajar.
  const figures = [FontFeature.tabularFigures()];
  TextStyle? weigh(TextStyle? s, FontWeight w) => s == null
      ? null
      : GoogleFonts.plusJakartaSans(
          textStyle: s, fontWeight: w, fontFeatures: figures);
  TextStyle? same(TextStyle? s) => s == null
      ? null
      : GoogleFonts.plusJakartaSans(textStyle: s, fontFeatures: figures);
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

ThemeData buildTheme(Brightness brightness) {
  final scheme =
      ColorScheme.fromSeed(seedColor: Brand.seed, brightness: brightness);
  final light = brightness == Brightness.light;
  final base = ThemeData(
      colorScheme: scheme, useMaterial3: true, brightness: brightness);
  final text = _firmer(GoogleFonts.plusJakartaSansTextTheme(base.textTheme));
  // Permukaan netral; warna merek hanya muncul di aksen dan angka.
  final bg = light ? const Color(0xFFF5F6F5) : const Color(0xFF101211);
  final surface = light ? Colors.white : const Color(0xFF1A1C1B);
  final outline = light ? const Color(0xFFE5E7E5) : const Color(0xFF2B2E2C);

  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: c, width: w),
      );

  return base.copyWith(
    scaffoldBackgroundColor: bg,
    textTheme: text,
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
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: outline),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border(outline),
      enabledBorder: border(outline),
      focusedBorder: border(scheme.primary, 1.6),
      errorBorder: border(scheme.error),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: text.labelLarge
            ?.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: outline),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: outline),
      backgroundColor: surface,
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: DividerThemeData(color: outline, space: 1),
  );
}
