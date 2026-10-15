// lib/features/meal_planner/presentation/widgets/bmi_gauge.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/bmi.dart';
import '../../../../core/utils/formatters.dart';

/// Semicircle BMI gauge: 4 bands (under / normal / over / obese) + needle.
class BmiGauge extends StatelessWidget {
  const BmiGauge({
    super.key,
    required this.bmi,
    this.standard = BmiStandard.asiaPacific,
    this.width = 140,
  });

  final double bmi;
  final BmiStandard standard;
  final double width;

  @override
  Widget build(BuildContext context) {
    final category = Bmi.categorize(bmi, standard: standard);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      label: 'Chỉ số BMI ${formatDecimal(bmi)}, ${category.label}',
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: Bmi.gaugePosition(bmi)),
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, position, _) => CustomPaint(
                size: Size(width, width / 2 + 8),
                painter: _GaugePainter(
                  position: position,
                  thresholds: Bmi.thresholds(standard),
                  trackColor: context.vl.skeletonBase,
                  needleColor: context.colors.onSurface,
                  surfaceColor: context.colors.surface,
                ),
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -30),
              child: Column(
                children: [
                  Text(formatDecimal(bmi),
                      style: AppTypography.mono(
                          size: 22,
                          weight: FontWeight.w700,
                          color: context.colors.onSurface)),
                  Text(
                    category.label,
                    style: context.textStyles.labelMedium?.copyWith(
                        color: _categoryTextColor(context, category)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _categoryTextColor(BuildContext context, BmiCategory c) => switch (c) {
        BmiCategory.normal => context.vl.onSuccessContainer,
        BmiCategory.underweight => context.vl.muted,
        BmiCategory.overweight ||
        BmiCategory.obese =>
          context.vl.onCautionContainer,
      };
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.position,
    required this.thresholds,
    required this.trackColor,
    required this.needleColor,
    required this.surfaceColor,
  });

  final double position;
  final BmiThresholds thresholds;
  final Color trackColor;
  final Color needleColor;
  final Color surfaceColor;

  static const double _stroke = 12;
  static const double _gap = 0.025; // radians between bands

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - _stroke / 2;
    final center = Offset(size.width / 2, size.height - 8);
    final rect = Rect.fromCircle(center: center, radius: radius);

    double toPos(double v) =>
        (v - Bmi.gaugeMin) / (Bmi.gaugeMax - Bmi.gaugeMin);
    final bands = <(double, double, Color)>[
      (0.0, toPos(thresholds.underweightBelow), AppColors.gray300),
      (
        toPos(thresholds.underweightBelow),
        toPos(thresholds.overweightFrom),
        AppColors.sprout500
      ),
      (
        toPos(thresholds.overweightFrom),
        toPos(thresholds.obeseFrom),
        AppColors.ochre300
      ),
      (toPos(thresholds.obeseFrom), 1.0, AppColors.ochre500),
    ];

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.butt;

    for (final (start, end, color) in bands) {
      final startAngle = math.pi + math.pi * start + _gap / 2;
      final sweep = math.pi * (end - start) - _gap;
      if (sweep <= 0) continue;
      canvas.drawArc(rect, startAngle, sweep, false, paint..color = color);
    }

    // Needle
    final angle = math.pi + math.pi * position;
    final tip =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + 2);
    final base =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius - 22);
    canvas.drawLine(
      base,
      tip,
      Paint()
        ..color = surfaceColor
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      base,
      tip,
      Paint()
        ..color = needleColor
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.position != position ||
      old.thresholds != thresholds ||
      old.needleColor != needleColor ||
      old.trackColor != trackColor;
}
