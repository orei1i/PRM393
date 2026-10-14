// lib/core/theme/vl_colors.dart
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Semantic colours Material's ColorScheme doesn't cover.
@immutable
class VLColors extends ThemeExtension<VLColors> {
  const VLColors({
    required this.caution,
    required this.cautionContainer,
    required this.onCautionContainer,
    required this.cautionBorder,
    required this.ai,
    required this.aiContainer,
    required this.onAiContainer,
    required this.aiBorder,
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.border,
    required this.muted,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.macroProtein,
    required this.macroCarbs,
    required this.macroFat,
    required this.macroFiber,
  });

  final Color caution;
  final Color cautionContainer;
  final Color onCautionContainer;
  final Color cautionBorder;
  final Color ai;
  final Color aiContainer;
  final Color onAiContainer;
  final Color aiBorder;
  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color border;
  final Color muted;
  final Color skeletonBase;
  final Color skeletonHighlight;
  final Color macroProtein;
  final Color macroCarbs;
  final Color macroFat;
  final Color macroFiber;

  static const light = VLColors(
    caution: AppColors.ochre500,
    cautionContainer: AppColors.ochre50,
    onCautionContainer: AppColors.ochre800,
    cautionBorder: AppColors.ochre300,
    ai: AppColors.ai600,
    aiContainer: AppColors.ai50,
    onAiContainer: AppColors.ai700,
    aiBorder: AppColors.ai200,
    success: AppColors.sprout500,
    successContainer: AppColors.sprout50,
    onSuccessContainer: AppColors.sprout800,
    border: AppColors.gray200,
    muted: AppColors.gray600,
    skeletonBase: AppColors.gray100,
    skeletonHighlight: AppColors.gray200,
    macroProtein: AppColors.sage800,
    macroCarbs: AppColors.sprout500,
    macroFat: AppColors.ochre500,
    macroFiber: AppColors.ai500,
  );

  static const dark = VLColors(
    caution: AppColors.ochre300,
    cautionContainer: Color(0xFF3A2A0A),
    onCautionContainer: AppColors.ochre300,
    cautionBorder: Color(0xFF6B4A12),
    ai: AppColors.ai400,
    aiContainer: Color(0xFF2A1F4D),
    onAiContainer: Color(0xFFC4B5FD),
    aiBorder: Color(0xFF3F2F73),
    success: AppColors.sprout400,
    successContainer: Color(0xFF12301F),
    onSuccessContainer: AppColors.sprout200,
    border: AppColors.darkBorder,
    muted: AppColors.darkMuted,
    skeletonBase: AppColors.darkSurfaceHigh,
    skeletonHighlight: AppColors.darkBorder,
    macroProtein: AppColors.sprout400,
    macroCarbs: AppColors.sprout200,
    macroFat: AppColors.ochre300,
    macroFiber: AppColors.ai400,
  );

  @override
  VLColors copyWith({
    Color? caution,
    Color? cautionContainer,
    Color? onCautionContainer,
    Color? cautionBorder,
    Color? ai,
    Color? aiContainer,
    Color? onAiContainer,
    Color? aiBorder,
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? border,
    Color? muted,
    Color? skeletonBase,
    Color? skeletonHighlight,
    Color? macroProtein,
    Color? macroCarbs,
    Color? macroFat,
    Color? macroFiber,
  }) {
    return VLColors(
      caution: caution ?? this.caution,
      cautionContainer: cautionContainer ?? this.cautionContainer,
      onCautionContainer: onCautionContainer ?? this.onCautionContainer,
      cautionBorder: cautionBorder ?? this.cautionBorder,
      ai: ai ?? this.ai,
      aiContainer: aiContainer ?? this.aiContainer,
      onAiContainer: onAiContainer ?? this.onAiContainer,
      aiBorder: aiBorder ?? this.aiBorder,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      border: border ?? this.border,
      muted: muted ?? this.muted,
      skeletonBase: skeletonBase ?? this.skeletonBase,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
      macroProtein: macroProtein ?? this.macroProtein,
      macroCarbs: macroCarbs ?? this.macroCarbs,
      macroFat: macroFat ?? this.macroFat,
      macroFiber: macroFiber ?? this.macroFiber,
    );
  }

  @override
  VLColors lerp(ThemeExtension<VLColors>? other, double t) {
    if (other is! VLColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return VLColors(
      caution: l(caution, other.caution),
      cautionContainer: l(cautionContainer, other.cautionContainer),
      onCautionContainer: l(onCautionContainer, other.onCautionContainer),
      cautionBorder: l(cautionBorder, other.cautionBorder),
      ai: l(ai, other.ai),
      aiContainer: l(aiContainer, other.aiContainer),
      onAiContainer: l(onAiContainer, other.onAiContainer),
      aiBorder: l(aiBorder, other.aiBorder),
      success: l(success, other.success),
      successContainer: l(successContainer, other.successContainer),
      onSuccessContainer: l(onSuccessContainer, other.onSuccessContainer),
      border: l(border, other.border),
      muted: l(muted, other.muted),
      skeletonBase: l(skeletonBase, other.skeletonBase),
      skeletonHighlight: l(skeletonHighlight, other.skeletonHighlight),
      macroProtein: l(macroProtein, other.macroProtein),
      macroCarbs: l(macroCarbs, other.macroCarbs),
      macroFat: l(macroFat, other.macroFat),
      macroFiber: l(macroFiber, other.macroFiber),
    );
  }
}

extension VLThemeContext on BuildContext {
  VLColors get vl => Theme.of(this).extension<VLColors>() ?? VLColors.light;
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get textStyles => Theme.of(this).textTheme;
}
