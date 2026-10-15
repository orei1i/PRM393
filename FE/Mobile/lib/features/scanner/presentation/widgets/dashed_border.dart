// lib/features/scanner/presentation/widgets/dashed_border.dart
import 'package:flutter/material.dart';

/// Dashed rounded-rect outline: the "needs confirmation" shape for
/// low-confidence detections (shape + text, never colour alone).
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.color,
    this.radius = 10,
    this.strokeWidth = 2,
    this.dash = 6,
    this.gap = 4,
    this.child,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(
          color: color,
          radius: radius,
          strokeWidth: strokeWidth,
          dash: dash,
          gap: gap),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dash,
    required this.gap,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          rect.deflate(strokeWidth / 2), Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth;
}
