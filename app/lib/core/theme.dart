import 'package:flutter/material.dart';

/// Token desain KIRA (docs/superpowers/design/kira-visual-direction.md). Terang: permukaan putih dingin; gelap:
/// abu-abu gelap ala Discord, bukan hitam pekat. Hijau-teal sebagai primer, kuning/amber hangat khusus untuk
/// "perlu perhatian" agar tidak menakut-nakuti, hijau untuk jalur perbaikan. Merah hanya untuk darurat.
/// Bentuk: kartu 18, input 14, chip 10, tombol pil.
class KiraSpace {
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32;
}

class KiraRadius {
  static const double card = 18, field = 14, chip = 10;
}

/// Warna semantik di luar peran Material 3.
@immutable
class KiraColors extends ThemeExtension<KiraColors> {
  const KiraColors({
    required this.attention,
    required this.attentionContainer,
    required this.onAttentionContainer,
    required this.improve,
    required this.improveContainer,
    required this.onImproveContainer,
    required this.chartNow,
    required this.chartBetter,
  });

  final Color attention;
  final Color attentionContainer;
  final Color onAttentionContainer;
  final Color improve;
  final Color improveContainer;
  final Color onImproveContainer;
  final Color chartNow;
  final Color chartBetter;

  static const light = KiraColors(
    attention: Color(0xFF8A6A00),
    attentionContainer: Color(0xFFFFF4C2),
    onAttentionContainer: Color(0xFF3C3518),
    improve: Color(0xFF1F7A4A),
    improveContainer: Color(0xFFD9F2E4),
    onImproveContainer: Color(0xFF06331D),
    chartNow: Color(0xFFB07F00),
    chartBetter: Color(0xFF0B6E6A),
  );

  static const dark = KiraColors(
    attention: Color(0xFFFEE75C),
    attentionContainer: Color(0xFF3C3518),
    onAttentionContainer: Color(0xFFFFF1A8),
    improve: Color(0xFF6FD3CB),
    improveContainer: Color(0xFF14432B),
    onImproveContainer: Color(0xFFD9F2E4),
    chartNow: Color(0xFFFEE75C),
    chartBetter: Color(0xFF6FD3CB),
  );

  @override
  KiraColors copyWith({
    Color? attention,
    Color? attentionContainer,
    Color? onAttentionContainer,
    Color? improve,
    Color? improveContainer,
    Color? onImproveContainer,
    Color? chartNow,
    Color? chartBetter,
  }) =>
      KiraColors(
        attention: attention ?? this.attention,
        attentionContainer: attentionContainer ?? this.attentionContainer,
        onAttentionContainer: onAttentionContainer ?? this.onAttentionContainer,
        improve: improve ?? this.improve,
        improveContainer: improveContainer ?? this.improveContainer,
        onImproveContainer: onImproveContainer ?? this.onImproveContainer,
        chartNow: chartNow ?? this.chartNow,
        chartBetter: chartBetter ?? this.chartBetter,
      );

  @override
  KiraColors lerp(ThemeExtension<KiraColors>? other, double t) {
    if (other is! KiraColors) return this;
    return KiraColors(
      attention: Color.lerp(attention, other.attention, t)!,
      attentionContainer: Color.lerp(attentionContainer, other.attentionContainer, t)!,
      onAttentionContainer: Color.lerp(onAttentionContainer, other.onAttentionContainer, t)!,
      improve: Color.lerp(improve, other.improve, t)!,
      improveContainer: Color.lerp(improveContainer, other.improveContainer, t)!,
      onImproveContainer: Color.lerp(onImproveContainer, other.onImproveContainer, t)!,
      chartNow: Color.lerp(chartNow, other.chartNow, t)!,
      chartBetter: Color.lerp(chartBetter, other.chartBetter, t)!,
    );
  }
}

extension KiraThemeX on BuildContext {
  /// Padding halaman biasa. Ruang bawah ditambah tinggi bilah navigasi sistem (tombol Home/Back atau bilah gestur) bila
  /// ada, supaya baris terakhir tidak tertutup; Android 15+ menggambar aplikasi sampai ke bawah bilah itu. Di dalam
  /// kerangka dengan bilah navigasi aplikasi nilainya sudah nol karena bilah itu yang menanggungnya.
  EdgeInsets get pagePadding =>
      EdgeInsets.fromLTRB(KiraSpace.lg, KiraSpace.lg, KiraSpace.lg, KiraSpace.lg + MediaQuery.paddingOf(this).bottom);

  KiraColors get kira => Theme.of(this).extension<KiraColors>()!;
  ColorScheme get scheme => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
}

const _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF0B6E6A),
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFCDEBE8),
  onPrimaryContainer: Color(0xFF04302E),
  secondary: Color(0xFF4A6360),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFDCE8E6),
  onSecondaryContainer: Color(0xFF0D1F1D),
  tertiary: Color(0xFF8A6A00),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFFF4C2),
  onTertiaryContainer: Color(0xFF3C3518),
  error: Color(0xFFB3261E),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF410E0B),
  surface: Color(0xFFF6F8F8),
  onSurface: Color(0xFF14201F),
  onSurfaceVariant: Color(0xFF4B5C5A),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFFFFFFF),
  surfaceContainer: Color(0xFFEEF2F1),
  surfaceContainerHigh: Color(0xFFE7EDEC),
  surfaceContainerHighest: Color(0xFFE0E8E6),
  outline: Color(0xFF6D7F7C),
  outlineVariant: Color(0xFFC9D3D1),
  shadow: Color(0xFF000000),
  inverseSurface: Color(0xFF223130),
  onInverseSurface: Color(0xFFEAF2F0),
  inversePrimary: Color(0xFF6FD3CB),
);

const _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF6FD3CB),
  onPrimary: Color(0xFF00201E),
  primaryContainer: Color(0xFF0B4A47),
  onPrimaryContainer: Color(0xFFCDEBE8),
  secondary: Color(0xFFB4CCC8),
  onSecondary: Color(0xFF1E3532),
  secondaryContainer: Color(0xFF334B48),
  onSecondaryContainer: Color(0xFFDCE8E6),
  tertiary: Color(0xFFFEE75C),
  onTertiary: Color(0xFF3C3518),
  tertiaryContainer: Color(0xFF3C3518),
  onTertiaryContainer: Color(0xFFFFF1A8),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  errorContainer: Color(0xFF8C1D18),
  onErrorContainer: Color(0xFFF9DEDC),
  surface: Color(0xFF313338),
  onSurface: Color(0xFFF2F3F5),
  onSurfaceVariant: Color(0xFFB5BAC1),
  surfaceContainerLowest: Color(0xFF2B2D31),
  surfaceContainerLow: Color(0xFF2B2D31),
  surfaceContainer: Color(0xFF35373C),
  surfaceContainerHigh: Color(0xFF383A40),
  surfaceContainerHighest: Color(0xFF404249),
  outline: Color(0xFF80848E),
  outlineVariant: Color(0xFF4E5058),
  shadow: Color(0xFF000000),
  inverseSurface: Color(0xFFF2F3F5),
  onInverseSurface: Color(0xFF313338),
  inversePrimary: Color(0xFF0B6E6A),
);

/// Skala tipe Material 3, satu keluarga (Figtree). Isi w400, judul w600, angka besar w800.
TextTheme _textTheme(Color ink, Color muted) {
  TextStyle s(double size, double height, FontWeight w, {double ls = 0, Color? color}) => TextStyle(
        fontFamily: 'Figtree',
        fontSize: size,
        height: height / size,
        fontWeight: w,
        letterSpacing: ls,
        color: color ?? ink,
      );
  return TextTheme(
    displayLarge: s(57, 64, FontWeight.w800, ls: -1),
    displayMedium: s(45, 52, FontWeight.w800, ls: -0.5),
    displaySmall: s(36, 44, FontWeight.w800),
    headlineLarge: s(32, 40, FontWeight.w600),
    headlineMedium: s(28, 36, FontWeight.w600),
    headlineSmall: s(24, 32, FontWeight.w600),
    titleLarge: s(22, 28, FontWeight.w600),
    titleMedium: s(16, 24, FontWeight.w600, ls: 0.1),
    titleSmall: s(14, 20, FontWeight.w600, ls: 0.1),
    bodyLarge: s(16, 24, FontWeight.w400, ls: 0.15),
    bodyMedium: s(14, 20, FontWeight.w400, ls: 0.2),
    bodySmall: s(12, 16, FontWeight.w400, ls: 0.3, color: muted),
    labelLarge: s(14, 20, FontWeight.w600, ls: 0.1),
    labelMedium: s(12, 16, FontWeight.w600, ls: 0.4),
    labelSmall: s(11, 16, FontWeight.w600, ls: 0.5, color: muted),
  );
}

ThemeData _build(ColorScheme scheme, KiraColors kira) {
  final text = _textTheme(scheme.onSurface, scheme.onSurfaceVariant);
  final stadium = const StadiumBorder();
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    fontFamily: 'Figtree',
    textTheme: text,
    extensions: [kira],
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KiraRadius.card),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.25)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: stadium,
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 24),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: stadium,
        side: BorderSide(color: scheme.outline),
        textStyle: text.labelLarge,
        padding: const EdgeInsets.symmetric(horizontal: 24),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), shape: stadium, textStyle: text.labelLarge),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KiraRadius.field),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KiraRadius.field),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(KiraRadius.field),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      helperStyle: text.bodySmall,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KiraRadius.chip)),
      side: BorderSide(color: scheme.outlineVariant),
      labelStyle: text.labelLarge,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      indicatorColor: scheme.primaryContainer,
      surfaceTintColor: Colors.transparent,
      height: 72,
      labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
    ),
    sliderTheme: SliderThemeData(
      trackHeight: 6,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.primaryContainer,
      thumbColor: scheme.primary,
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KiraRadius.field)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
  );
}

final ThemeData kiraLightTheme = _build(_lightScheme, KiraColors.light);
final ThemeData kiraDarkTheme = _build(_darkScheme, KiraColors.dark);

/// Rasio kontras WCAG antara dua warna.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
