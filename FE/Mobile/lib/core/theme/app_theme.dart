// lib/core/theme/app_theme.dart
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';
import 'vl_colors.dart';

abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.sage800,
      brightness: brightness,
    ).copyWith(
      primary: isLight ? AppColors.sage800 : AppColors.sprout400,
      onPrimary: isLight ? Colors.white : AppColors.sprout950,
      primaryContainer: isLight ? AppColors.sage100 : AppColors.sage700,
      onPrimaryContainer: isLight ? AppColors.sage900 : AppColors.darkInk,
      secondary: AppColors.sprout500,
      onSecondary: AppColors.sprout950,
      secondaryContainer: isLight ? AppColors.sage50 : AppColors.darkSurfaceHigh,
      onSecondaryContainer: isLight ? AppColors.sage800 : AppColors.darkInk,
      tertiary: isLight ? AppColors.ai600 : AppColors.ai400,
      onTertiary: isLight ? Colors.white : const Color(0xFF1E1240),
      error: isLight ? AppColors.danger700 : const Color(0xFFF87171),
      onError: isLight ? Colors.white : const Color(0xFF450A0A),
      surface: isLight ? Colors.white : AppColors.darkSurface,
      onSurface: isLight ? AppColors.gray900 : AppColors.darkInk,
      onSurfaceVariant: isLight ? AppColors.gray600 : AppColors.darkMuted,
      surfaceContainerLowest: isLight ? Colors.white : AppColors.darkBackground,
      surfaceContainerLow: isLight ? AppColors.gray50 : AppColors.darkSurface,
      surfaceContainer: isLight ? AppColors.gray100 : AppColors.darkSurfaceHigh,
      surfaceContainerHigh: isLight ? AppColors.gray100 : AppColors.darkSurfaceHigh,
      outline: isLight ? AppColors.gray300 : AppColors.darkBorder,
      outlineVariant: isLight ? AppColors.gray200 : AppColors.darkBorder,
    );

    final text = AppTypography.textTheme(brightness).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    final background = isLight ? AppColors.gray50 : AppColors.darkBackground;
    final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: background,
      extensions: [isLight ? VLColors.light : VLColors.dark],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: buttonShape,
          textStyle: text.labelLarge?.copyWith(fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: buttonShape,
          side: BorderSide(color: scheme.outline),
          foregroundColor: scheme.onSurface,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          foregroundColor: scheme.primary,
          textStyle: text.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: text.labelMedium,
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: scheme.surface,
        indicatorColor: isLight ? AppColors.sage100 : AppColors.sage700,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? AppColors.gray900 : AppColors.darkInk,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: isLight ? Colors.white : AppColors.gray900,
        ),
        actionTextColor: isLight ? AppColors.sprout400 : AppColors.sage800,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }
}
