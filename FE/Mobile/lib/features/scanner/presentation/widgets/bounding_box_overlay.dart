// lib/features/scanner/presentation/widgets/bounding_box_overlay.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/detected_ingredient.dart';
import 'dashed_border.dart';

/// Draws detection boxes over a frame shown with `BoxFit.cover`.
/// Boxes are mapped from frame space to viewport space so labels keep their
/// real size (they are not scaled by the FittedBox).
class BoundingBoxOverlay extends StatelessWidget {
  const BoundingBoxOverlay({
    super.key,
    required this.items,
    required this.frameSize,
    required this.onTapItem,
  });

  final List<DetectedIngredient> items;
  final Size frameSize;
  final ValueChanged<DetectedIngredient> onTapItem;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        final scale = math.max(viewport.width / frameSize.width,
            viewport.height / frameSize.height);
        final dx = (viewport.width - frameSize.width * scale) / 2;
        final dy = (viewport.height - frameSize.height * scale) / 2;

        Rect toViewport(NormalizedBox b) => Rect.fromLTWH(
              dx + b.left * frameSize.width * scale,
              dy + b.top * frameSize.height * scale,
              b.width * frameSize.width * scale,
              b.height * frameSize.height * scale,
            );

        return Stack(
          children: [
            for (final (index, item) in items.indexed)
              if (item.box != null)
                _AnimatedBox(
                  key: ValueKey(item.id),
                  rect: toViewport(item.box!),
                  item: item,
                  delay: Duration(milliseconds: 80 * index),
                  onTap: () => onTapItem(item),
                ),
          ],
        );
      },
    );
  }
}

class _AnimatedBox extends StatelessWidget {
  const _AnimatedBox({
    super.key,
    required this.rect,
    required this.item,
    required this.delay,
    required this.onTap,
  });

  final Rect rect;
  final DetectedIngredient item;
  final Duration delay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final confident = item.confirmed;
    final boxColor = confident ? AppColors.sprout500 : const Color(0xFFF59E0B);
    final percent = '${(item.confidence * 100).round()}%';
    final label = confident ? item.name : '${item.name}?';
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Positioned.fromRect(
      rect: rect,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 240) + delay,
        curve: Interval(
          reduceMotion
              ? 0
              : delay.inMilliseconds / (240 + delay.inMilliseconds),
          1,
          curve: Curves.easeOutBack,
        ),
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0).toDouble(),
          child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
        ),
        child: Semantics(
          button: true,
          label: confident
              ? '$label, độ tin cậy $percent, ${item.freshness.label}'
              : 'Cần xác nhận: $label, độ tin cậy $percent',
          excludeSemantics: true,
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: confident
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: boxColor, width: 2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        )
                      : DashedBorder(
                          color: boxColor,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(color: Color(0x14F59E0B)),
                          ),
                        ),
                ),
                Positioned(
                  left: -2,
                  top: -26,
                  child: Container(
                    height: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                        color: boxColor,
                        borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(percent,
                            style: AppTypography.mono(
                                size: 11,
                                weight: FontWeight.w700,
                                color: const Color(0xFF111827))),
                      ],
                    ),
                  ),
                ),
                if (confident && item.freshness != Freshness.unknown)
                  Positioned(
                      right: 4,
                      bottom: 4,
                      child: FreshnessBadge(freshness: item.freshness)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Tươi" / "Dùng sớm" / "Kém tươi" pill. Visual estimate only.
class FreshnessBadge extends StatelessWidget {
  const FreshnessBadge(
      {super.key, required this.freshness, this.onDark = true});

  final Freshness freshness;
  final bool onDark;

  static Color dotColor(Freshness f) => switch (f) {
        Freshness.fresh => AppColors.sprout500,
        Freshness.useSoon => const Color(0xFFF59E0B),
        Freshness.pastPrime => AppColors.gray500,
        Freshness.unknown => AppColors.gray300,
      };

  @override
  Widget build(BuildContext context) {
    final textColor = onDark
        ? switch (freshness) {
            Freshness.fresh => AppColors.sprout200,
            Freshness.useSoon => AppColors.ochre200,
            _ => AppColors.gray300,
          }
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: onDark
            ? const Color(0x99000000)
            : Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: dotColor(freshness), shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(freshness.label,
              style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: textColor)),
        ],
      ),
    );
  }
}
