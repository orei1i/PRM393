// lib/core/theme/app_typography.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Plus Jakarta Sans for UI, JetBrains Mono (tabular) for nutrition numbers.
abstract final class AppTypography {
  static TextTheme textTheme(Brightness brightness) {
    final base = brightness == Brightness.light
        ? ThemeData.light(useMaterial3: true).textTheme
        : ThemeData.dark(useMaterial3: true).textTheme;
    final t = GoogleFonts.plusJakartaSansTextTheme(base);

    return t.copyWith(
      displaySmall: t.displaySmall?.copyWith(fontSize: 32, height: 38 / 32, fontWeight: FontWeight.w800, letterSpacing: -0.6),
      headlineSmall: t.headlineSmall?.copyWith(fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w800, letterSpacing: -0.3),
      titleLarge: t.titleLarge?.copyWith(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w800, letterSpacing: -0.2),
      titleMedium: t.titleMedium?.copyWith(fontSize: 17, height: 24 / 17, fontWeight: FontWeight.w700),
      titleSmall: t.titleSmall?.copyWith(fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w700),
      bodyLarge: t.bodyLarge?.copyWith(fontSize: 15, height: 22 / 15, fontWeight: FontWeight.w400),
      bodyMedium: t.bodyMedium?.copyWith(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400),
      bodySmall: t.bodySmall?.copyWith(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500),
      labelLarge: t.labelLarge?.copyWith(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700),
      labelMedium: t.labelMedium?.copyWith(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600),
      labelSmall: t.labelSmall?.copyWith(fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w700, letterSpacing: 0.4),
    );
  }

  /// Numbers: kcal, grams, BMI, confidence %.
  static TextStyle mono({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color? color,
    double? height,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
