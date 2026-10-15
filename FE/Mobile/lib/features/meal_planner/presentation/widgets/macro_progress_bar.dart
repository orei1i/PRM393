// lib/features/meal_planner/presentation/widgets/macro_progress_bar.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/meal_plan.dart';

/// One macro: label, value/target and an animated bar.
/// Over 110 % adds a text tag ("vượt") so the state never relies on colour alone.
class MacroProgressBar extends StatelessWidget {
  const MacroProgressBar({
    super.key,
    required this.label,
    required this.value,
    required this.target,
    required this.color,
    this.unit = 'g',
  });

  final String label;
  final double value;
  final double target;
  final Color color;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final ratio = target <= 0 ? 0.0 : value / target;
    final over = ratio > 1.1;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label:
          '$label ${value.round()} trên ${target.round()} $unit${over ? ', vượt mục tiêu' : ''}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: context.textStyles.labelMedium),
              const Spacer(),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                        text: '${value.round()}',
                        style: AppTypography.mono(
                            size: 12, color: context.colors.onSurface)),
                    TextSpan(
                        text: '/${target.round()} $unit',
                        style: AppTypography.mono(
                            size: 12,
                            weight: FontWeight.w500,
                            color: context.vl.muted)),
                    if (over)
                      TextSpan(
                        text: '  vượt',
                        style: context.textStyles.labelSmall
                            ?.copyWith(color: context.vl.onCautionContainer),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: context.vl.skeletonBase),
                  TweenAnimationBuilder<double>(
                    tween:
                        Tween(begin: 0, end: ratio.clamp(0.0, 1.0).toDouble()),
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (context, factor, _) => FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: factor,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(999)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Thứ Tư, 14/10 · 1.670 / 1.850 kcal" + 4 macro bars.
class DailyMacroCard extends StatelessWidget {
  const DailyMacroCard(
      {super.key,
      required this.date,
      required this.totals,
      required this.targets});

  final DateTime date;
  final Nutrition totals;
  final Nutrition targets;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final kcalRatio =
        targets.calories == 0 ? 0.0 : totals.calories / targets.calories;

    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                  child: Text(formatLongDate(date),
                      style: context.textStyles.titleSmall)),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: formatInt(totals.calories),
                      style: AppTypography.mono(
                          size: 18,
                          weight: FontWeight.w700,
                          color: context.colors.onSurface)),
                  TextSpan(
                      text: ' / ${formatInt(targets.calories)} kcal',
                      style: AppTypography.mono(
                          size: 12, weight: FontWeight.w500, color: vl.muted)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: kcalRatio.clamp(0.0, 1.0).toDouble(),
              minHeight: 6,
              color: kcalRatio > 1.1 ? vl.caution : vl.success,
              backgroundColor: vl.skeletonBase,
              semanticsLabel: 'Năng lượng trong ngày',
              semanticsValue:
                  '${formatInt(totals.calories)} trên ${formatInt(targets.calories)} kcal',
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = (constraints.maxWidth - 16) / 2;
              return Wrap(
                spacing: 16,
                runSpacing: 14,
                children: [
                  SizedBox(
                      width: itemWidth,
                      child: MacroProgressBar(
                          label: 'Đạm',
                          value: totals.proteinG,
                          target: targets.proteinG,
                          color: vl.macroProtein)),
                  SizedBox(
                      width: itemWidth,
                      child: MacroProgressBar(
                          label: 'Tinh bột',
                          value: totals.carbsG,
                          target: targets.carbsG,
                          color: vl.macroCarbs)),
                  SizedBox(
                      width: itemWidth,
                      child: MacroProgressBar(
                          label: 'Chất béo',
                          value: totals.fatG,
                          target: targets.fatG,
                          color: vl.macroFat)),
                  SizedBox(
                      width: itemWidth,
                      child: MacroProgressBar(
                          label: 'Chất xơ',
                          value: totals.fiberG,
                          target: targets.fiberG,
                          color: vl.macroFiber)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
