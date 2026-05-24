import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// App theme — single source of truth. Navy primary + amber accent.
/// Inter for UI text, Space Grotesk for numbers/display.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primary = isDark ? BrandColors.navyDark : BrandColors.navy;
    final secondary = BrandColors.amber;
    final surface = isDark ? BrandColors.surfaceDark : BrandColors.surfaceLight;
    final surfaceElev = isDark ? BrandColors.surfaceElevDark : BrandColors.surfaceElevLight;
    final outline = isDark ? BrandColors.outlineDark : BrandColors.outlineLight;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      secondary: secondary,
      surface: surface,
      // map Material's error to our danger token so colorScheme.error stays
      // semantically consistent with GarageColors.danger
      error: isDark ? const Color(0xFFE5675C) : const Color(0xFFC13B2E),
      outline: outline,
    );

    final extensions = <ThemeExtension<dynamic>>[
      isDark ? GarageColors.dark : GarageColors.light,
    ];

    // Inter for body/UI, Space Grotesk for display (numbers / hero text).
    final baseText = isDark
        ? GoogleFonts.interTextTheme(ThemeData.dark().textTheme)
        : GoogleFonts.interTextTheme(ThemeData.light().textTheme);
    final display = GoogleFonts.spaceGroteskTextTheme(baseText);

    // Splice: keep Inter for everything *except* display-level styles
    // (display* / headline*), which use Space Grotesk for that engineering feel.
    final textTheme = baseText.copyWith(
      displayLarge: display.displayLarge?.copyWith(fontWeight: FontWeight.w700),
      displayMedium: display.displayMedium?.copyWith(fontWeight: FontWeight.w700),
      displaySmall: display.displaySmall?.copyWith(fontWeight: FontWeight.w600),
      headlineLarge: display.headlineLarge?.copyWith(fontWeight: FontWeight.w600),
      headlineMedium: display.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
      headlineSmall: display.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      extensions: extensions,
      textTheme: textTheme,
      scaffoldBackgroundColor: surface,
      dividerTheme: DividerThemeData(color: outline.withValues(alpha: 0.6)),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        shadowColor: isDark ? Colors.transparent : Colors.black.withValues(alpha: 0.06),
        color: surfaceElev,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          side: BorderSide(color: outline),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: secondary,
        foregroundColor: Colors.black,
        elevation: 2,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? const Color(0xFF1E232B) : const Color(0xFFEEF1F5),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: textTheme.labelMedium,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1B1F26) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceElev,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}
