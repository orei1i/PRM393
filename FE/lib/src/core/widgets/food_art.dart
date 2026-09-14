import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Offline, resolution-independent editorial food illustration.
class FoodArt extends StatelessWidget {
  const FoodArt({this.variant = 0, this.height = 190, super.key});
  final int variant;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Illustration of a colorful plant-based meal',
    image: true,
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(painter: _FoodPainter(variant)),
      ),
    ),
  );
}

class _FoodPainter extends CustomPainter {
  _FoodPainter(this.variant);
  final int variant;

  @override
  void paint(Canvas canvas, Size size) {
    const backgrounds = [
      Color(0xFFE7EEDB),
      Color(0xFFF0E4D5),
      Color(0xFFE2EAE4),
      Color(0xFFF2E9CF),
    ];
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = backgrounds[variant % backgrounds.length],
    );
    final center = Offset(size.width * .52, size.height * .53);
    final radius = math.min(size.width * .33, size.height * .45);
    canvas.drawCircle(
      center + const Offset(3, 6),
      radius + 7,
      Paint()
        ..color = const Color(0xFF24482B).withValues(alpha: .13)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      center,
      radius + 7,
      Paint()..color = const Color(0xFFFCFAF3),
    );
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFFD7DDC5));
    final random = math.Random(variant + 8);
    const ingredients = [
      Color(0xFF3C733D),
      Color(0xFF8FAD58),
      Color(0xFFD98B45),
      Color(0xFFB84436),
      Color(0xFFE2CB89),
      Color(0xFF75944A),
    ];
    for (var i = 0; i < 100; i++) {
      final angle = random.nextDouble() * math.pi * 2;
      final distance = math.sqrt(random.nextDouble()) * (radius - 8);
      final point =
          center +
          Offset(math.cos(angle) * distance, math.sin(angle) * distance);
      final ingredient = Paint()
        ..color = ingredients[(i + variant) % ingredients.length];
      canvas.save();
      canvas.translate(point.dx, point.dy);
      canvas.rotate(angle);
      if (i % 3 == 0) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: 20, height: 10),
          ingredient,
        );
        canvas.drawLine(
          const Offset(-7, 0),
          const Offset(7, 0),
          Paint()
            ..color = Colors.white.withValues(alpha: .18)
            ..strokeWidth = 1,
        );
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: 9 + random.nextDouble() * 9,
              height: 8,
            ),
            const Radius.circular(3),
          ),
          ingredient,
        );
      }
      canvas.restore();
    }
    final leafPaint = Paint()..color = const Color(0xFF557347);
    canvas.save();
    canvas.translate(size.width * .12, size.height * .75);
    canvas.rotate(-.5);
    for (var i = 0; i < 4; i++) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(i * 7, -i * 10), width: 18, height: 8),
        leafPaint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FoodPainter oldDelegate) =>
      oldDelegate.variant != variant;
}
