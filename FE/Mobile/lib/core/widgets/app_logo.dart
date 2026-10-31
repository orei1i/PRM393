// lib/core/widgets/app_logo.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The VeganLife leaf: a pointed leaf rising to the top right with its
/// midrib cut out and a short curved stem, the same silhouette as the
/// app-bar mark. Painted (no icon font), so it renders identically in
/// widget tests and in the launcher / splash PNGs made by
/// `tool/brand/render_brand_assets_test.dart`.
class VeganLifeLeafPainter extends CustomPainter {
  const VeganLifeLeafPainter({required this.color});

  final Color color;

  /// Paints the leaf into [rect] (square works best).
  static void paintLeaf(Canvas canvas, Rect rect, Color color) {
    final s = rect.shortestSide;
    final c = rect.center;
    // Local frame: base of the blade at x = 0, tip at x = blade, midrib on
    // y = 0; the whole mark is turned 45° so the tip points up-right.
    final blade = s * 0.80;
    final half = s * 0.24;
    final stem = s * 0.20;
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    canvas.save();
    // Centre the stem-to-tip diagonal in the rect.
    final span = blade + stem;
    canvas.translate(c.dx, c.dy);
    canvas.rotate(-math.pi / 4);
    canvas.translate(-span / 2 + stem, 0);

    final leaf = Path()
      ..moveTo(0, 0)
      ..cubicTo(
          blade * 0.10, -half * 1.05, blade * 0.55, -half * 1.15, blade, 0)
      ..cubicTo(blade * 0.55, half * 1.15, blade * 0.10, half * 1.05, 0, 0)
      ..close();

    canvas.saveLayer(Rect.fromLTRB(-stem - s, -s, blade + s, s), Paint());
    canvas.drawPath(leaf, paint);
    // The midrib, cut out of the blade.
    final cut = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.05;
    canvas.drawLine(Offset(blade * 0.24, 0), Offset(blade * 0.76, 0), cut);
    canvas.restore();

    // Stem, from inside the blade and curving slightly down past its base.
    final stemPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.07
      ..isAntiAlias = true;
    final stemPath = Path()
      ..moveTo(blade * 0.10, 0)
      ..quadraticBezierTo(-stem * 0.45, 0, -stem, stem * 0.32);
    canvas.drawPath(stemPath, stemPaint);
    canvas.restore();
  }

  /// The launcher / splash badge: a sage disc (or rounded square) with a
  /// white leaf. [leafScale] is the leaf box relative to the badge.
  static void paintBadge(
    Canvas canvas,
    Rect rect, {
    bool circle = true,
    double cornerRadius = 0.22,
    double leafScale = 0.62,
    bool background = true,
  }) {
    if (background) {
      final shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.sage700, AppColors.sage800],
      ).createShader(rect);
      final fill = Paint()
        ..shader = shader
        ..isAntiAlias = true;
      if (circle) {
        canvas.drawOval(rect, fill);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                rect, Radius.circular(rect.shortestSide * cornerRadius)),
            fill);
      }
    }
    final leafSide = rect.shortestSide * leafScale;
    paintLeaf(
      canvas,
      Rect.fromCenter(center: rect.center, width: leafSide, height: leafSide),
      Colors.white,
    );
  }

  @override
  void paint(Canvas canvas, Size size) =>
      paintLeaf(canvas, Offset.zero & size, color);

  @override
  bool shouldRepaint(VeganLifeLeafPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _BadgePainter extends CustomPainter {
  const _BadgePainter();

  @override
  void paint(Canvas canvas, Size size) =>
      VeganLifeLeafPainter.paintBadge(canvas, Offset.zero & size);

  @override
  bool shouldRepaint(_BadgePainter oldDelegate) => false;
}

/// The leaf alone, in [color] (the theme's primary by default).
class VeganLifeMark extends StatelessWidget {
  const VeganLifeMark({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'VeganLife',
      image: true,
      child: CustomPaint(
        size: Size.square(size),
        painter: VeganLifeLeafPainter(
            color: color ?? Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

/// The app icon as a round badge (sage disc, white leaf): splash, Welcome,
/// sign-in prompts.
class VeganLifeBadge extends StatelessWidget {
  const VeganLifeBadge({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'VeganLife',
      image: true,
      child:
          CustomPaint(size: Size.square(size), painter: const _BadgePainter()),
    );
  }
}

/// Mark + "VeganLife" wordmark. Without [textStyle] the wordmark inherits
/// the surrounding style (an AppBar title gets the title style).
class VeganLifeLogo extends StatelessWidget {
  const VeganLifeLogo({
    super.key,
    this.size = 24,
    this.textStyle,
    this.badge = false,
    this.gap = 8,
  });

  /// Height of the mark (or badge).
  final double size;
  final TextStyle? textStyle;

  /// The round badge instead of the bare leaf.
  final bool badge;
  final double gap;

  @override
  Widget build(BuildContext context) {
    // Shrinks rather than overflows in a tight app bar (large text, narrow
    // phone); at its natural size otherwise.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExcludeSemantics(
            child:
                badge ? VeganLifeBadge(size: size) : VeganLifeMark(size: size),
          ),
          SizedBox(width: gap),
          Text('VeganLife', style: textStyle),
        ],
      ),
    );
  }
}
