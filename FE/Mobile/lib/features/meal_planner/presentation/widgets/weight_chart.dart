// lib/features/meal_planner/presentation/widgets/weight_chart.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/body_progress.dart';

/// Line chart of weight or BMI over time (drawn with a [CustomPainter], no
/// chart package): the healthy band shaded behind, one dot per day, the
/// axis' top and bottom values on the left and the first and last dates
/// below. Needs at least 1 of [points]; one point is a lone dot in the middle.
class WeightChart extends StatelessWidget {
  const WeightChart({
    super.key,
    required this.points,
    required this.band,
    required this.series,
    required this.semanticsLabel,
    this.height = 180,
    this.previewLast = false,
  });

  /// Oldest first.
  final List<ChartPoint> points;

  /// Healthy range in the series' unit (kg or BMI).
  final ({double min, double max}) band;
  final MetricsSeries series;

  /// Read out instead of the drawing ("Cân nặng từ 65,0 đến 66,0 kg trong
  /// 30 ngày").
  final String semanticsLabel;
  final double height;

  /// The last point isn't saved yet: it is filled and its segment dashed.
  final bool previewLast;

  /// The visible value range: the data with some air, stretched to the
  /// band's nearest edge when every point is outside the band (so the gap
  /// to the healthy range shows).
  static ({double min, double max}) yRange(
      List<ChartPoint> points, ({double min, double max}) band,
      {required double minSpan}) {
    var lo = points.map((p) => p.value).reduce(math.min);
    var hi = points.map((p) => p.value).reduce(math.max);
    if (lo > band.max) lo = band.max;
    if (hi < band.min) hi = band.min;
    if (hi - lo < minSpan) {
      final mid = (hi + lo) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
    }
    final pad = (hi - lo) * 0.12;
    return (min: lo - pad, max: hi + pad);
  }

  @override
  Widget build(BuildContext context) {
    final range = yRange(points, band,
        minSpan: series == MetricsSeries.weight ? 1.0 : 0.4);
    final muted =
        context.textStyles.labelSmall?.copyWith(color: context.vl.muted);
    return Semantics(
      container: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDecimal(range.max), style: muted),
                Text(formatDecimal(range.min), style: muted),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: height,
                  child: CustomPaint(
                    painter: WeightChartPainter(
                      points: points,
                      band: band,
                      range: range,
                      lineColor: context.colors.primary,
                      dotFill: context.colors.surface,
                      bandColor: context.vl.successContainer,
                      gridColor: context.vl.border,
                      previewLast: previewLast,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (points.first.day == points.last.day)
                  Text(formatDayMonth(points.last.day),
                      textAlign: TextAlign.center, style: muted)
                else
                  Row(
                    children: [
                      Text(formatDayMonth(points.first.day), style: muted),
                      const Spacer(),
                      Text(formatDayMonth(points.last.day), style: muted),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class WeightChartPainter extends CustomPainter {
  WeightChartPainter({
    required this.points,
    required this.band,
    required this.range,
    required this.lineColor,
    required this.dotFill,
    required this.bandColor,
    required this.gridColor,
    this.previewLast = false,
  });

  final List<ChartPoint> points;
  final ({double min, double max}) band;
  final ({double min, double max}) range;
  final Color lineColor;
  final Color dotFill;
  final Color bandColor;
  final Color gridColor;
  final bool previewLast;

  static const _inset = 6.0;
  static const _dash = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    const top = _inset;
    final bottom = size.height - _inset;
    const left = _inset;
    final right = size.width - _inset;
    double y(double v) =>
        bottom - (v - range.min) / (range.max - range.min) * (bottom - top);

    final first = points.first.day;
    final spanDays = points.last.day.difference(first).inHours / 24;
    double x(DateTime day) => spanDays <= 0
        ? (left + right) / 2
        : left + day.difference(first).inHours / 24 / spanDays * (right - left);

    // Healthy band, clipped to what is visible.
    final bandTop = y(math.min(band.max, range.max));
    final bandBottom = y(math.max(band.min, range.min));
    if (bandBottom > bandTop) {
      canvas.drawRect(Rect.fromLTRB(0, bandTop, size.width, bandBottom),
          Paint()..color = bandColor);
    }

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    canvas
      ..drawLine(const Offset(0, top), Offset(size.width, top), grid)
      ..drawLine(Offset(0, bottom), Offset(size.width, bottom), grid);

    final offsets = [for (final p in points) Offset(x(p.day), y(p.value))];
    final solid = previewLast ? offsets.length - 1 : offsets.length;
    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final o in offsets.skip(1).take(math.max(0, solid - 1))) {
      path.lineTo(o.dx, o.dy);
    }
    final line = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, line);
    if (previewLast && offsets.length >= 2) {
      final from = offsets[offsets.length - 2];
      final to = offsets.last;
      final length = (to - from).distance;
      for (var d = 0.0; d < length; d += _dash * 2) {
        final end = math.min(d + _dash, length);
        canvas.drawLine(Offset.lerp(from, to, d / length)!,
            Offset.lerp(from, to, end / length)!, line);
      }
    }
    final fill = Paint()..color = dotFill;
    final previewFill = Paint()..color = lineColor;
    final ring = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final (i, o) in offsets.indexed) {
      final last = i == offsets.length - 1;
      final r = last ? 5.0 : 3.5;
      canvas
        ..drawCircle(o, r, last && previewLast ? previewFill : fill)
        ..drawCircle(o, r, ring);
    }
  }

  @override
  bool shouldRepaint(WeightChartPainter old) =>
      old.points != points ||
      old.band != band ||
      old.range != range ||
      old.lineColor != lineColor ||
      old.dotFill != dotFill ||
      old.bandColor != bandColor ||
      old.gridColor != gridColor ||
      old.previewLast != previewLast;
}
