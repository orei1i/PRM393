// lib/features/scanner/presentation/widgets/mock_fridge_preview.dart
import 'package:flutter/material.dart';

/// Stylised fridge interior used when no camera is available (emulator,
/// desktop, mock mode). Shapes sit inside the mock detection boxes.
class MockFridgePreview extends StatelessWidget {
  const MockFridgePreview({super.key});

  /// Logical frame the mock boxes are normalised against (3:4 portrait).
  static const Size frameSize = Size(600, 800);

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(painter: _FridgePainter(), size: frameSize);
  }
}

class _FridgePainter extends CustomPainter {
  const _FridgePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    Offset p(double x, double y) => Offset(x * w, y * h);
    Paint fill(int argb) => Paint()..color = Color(argb);

    canvas.drawRect(Offset.zero & size, fill(0xFF121A17));
    canvas.drawRect(Rect.fromLTWH(0, 0.12 * h, w, 0.68 * h), fill(0xFF1B2722));

    // Shelves
    for (final y in const [0.385, 0.555, 0.715]) {
      canvas.drawRect(Rect.fromLTWH(0, y * h, w, 0.008 * h), fill(0xFF2E3E36));
    }

    // Broccoli (box 0.05, 0.17, 0.30 × 0.20)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0.18 * w, 0.28 * h, 0.04 * w, 0.09 * h),
          const Radius.circular(6)),
      fill(0xFF6E8F5E),
    );
    for (final (x, y, r, c) in const [
      (0.15, 0.24, 0.055, 0xFF3E6B44),
      (0.22, 0.225, 0.06, 0xFF4D7C50),
      (0.28, 0.25, 0.05, 0xFF3B6541),
      (0.11, 0.28, 0.045, 0xFF456F47),
      (0.20, 0.27, 0.05, 0xFF52824F),
    ]) {
      canvas.drawCircle(p(x, y), r * w, fill(c));
    }

    // Tofu block (box 0.40, 0.19, 0.27 × 0.18)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0.42 * w, 0.24 * h, 0.23 * w, 0.13 * h),
          const Radius.circular(8)),
      fill(0xFFD6CFBA),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0.42 * w, 0.24 * h, 0.23 * w, 0.025 * h),
          const Radius.circular(8)),
      fill(0xFFE6E0CC),
    );

    // Tomatoes (box 0.71, 0.21, 0.25 × 0.15)
    canvas.drawCircle(p(0.78, 0.31), 0.055 * w, fill(0xFFA8473A));
    canvas.drawCircle(p(0.89, 0.315), 0.05 * w, fill(0xFFB85544));

    // Egg carton (box 0.05, 0.43, 0.36 × 0.12)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0.07 * w, 0.49 * h, 0.32 * w, 0.055 * h),
          const Radius.circular(6)),
      fill(0xFF8C8577),
    );
    for (final x in const [0.12, 0.19, 0.26, 0.33]) {
      canvas.drawOval(
          Rect.fromCenter(
              center: p(x, 0.478), width: 0.06 * w, height: 0.055 * h),
          fill(0xFFF1E3C8));
    }

    // Milk carton (box 0.45, 0.40, 0.17 × 0.15)
    canvas.drawRect(Rect.fromLTWH(0.47 * w, 0.445 * h, 0.13 * w, 0.103 * h),
        fill(0xFFE8EEF2));
    canvas.drawPath(
      Path()
        ..moveTo(0.47 * w, 0.445 * h)
        ..lineTo(0.535 * w, 0.41 * h)
        ..lineTo(0.60 * w, 0.445 * h)
        ..close(),
      fill(0xFFD3DCE3),
    );
    canvas.drawRect(Rect.fromLTWH(0.47 * w, 0.475 * h, 0.13 * w, 0.03 * h),
        fill(0xFF4A7BB7));

    // Carrots (box 0.05, 0.58, 0.42 × 0.13)
    final carrot = fill(0xFFC2672C);
    for (final y in const [0.61, 0.645, 0.68]) {
      final path = Path()
        ..moveTo(0.08 * w, (y - 0.016) * h)
        ..lineTo(0.45 * w, y * h)
        ..lineTo(0.08 * w, (y + 0.016) * h)
        ..close();
      canvas.drawPath(path, carrot);
      canvas.drawLine(
          p(0.08, y),
          p(0.05, y - 0.02),
          Paint()
            ..color = const Color(0xFF4F7A3F)
            ..strokeWidth = 0.012 * w
            ..strokeCap = StrokeCap.round);
    }

    // Leafy greens (box 0.52, 0.585, 0.43 × 0.12)
    for (final (x, y, rx, ry, c) in const [
      (0.60, 0.645, 0.08, 0.03, 0xFF2E5636),
      (0.72, 0.62, 0.09, 0.032, 0xFF35603C),
      (0.85, 0.645, 0.08, 0.03, 0xFF2A4F33),
      (0.73, 0.68, 0.18, 0.025, 0xFF305A38),
    ]) {
      canvas.drawOval(
          Rect.fromCenter(
              center: p(x, y), width: rx * 2 * w, height: ry * 2 * h),
          fill(c));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
