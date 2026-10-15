// lib/features/scanner/presentation/widgets/bounding_box_overlay.dart
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/detected_ingredient.dart';
import 'dashed_border.dart';

/// Draws detection boxes over a frame shown with `BoxFit.cover`.
/// Boxes are mapped from frame space to viewport space so labels keep their
/// real size (they are not scaled by the FittedBox). Each box has a name chip
/// (on its top edge) and a "Thuần chay" / "Không thuần chay" badge (in its
/// bottom corner when it fits); green boxes are vegan, red ones are not,
/// dashed amber ones still need confirming. Chips of all boxes are laid out
/// together by [layoutDetectionChips], so they never cover each other or a
/// neighbouring box, and stay inside the preview.
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

  /// Test hooks: the name chip and the vegan badge of a detection.
  static Key labelKey(String id) => ValueKey('scan-label-$id');
  static Key badgeKey(String id) => ValueKey('scan-badge-$id');

  @override
  Widget build(BuildContext context) {
    final safe = MediaQuery.paddingOf(context);
    // Chips stay inside the visible preview (and off the status bar), even
    // when `BoxFit.cover` crops the box itself at the screen edge.
    final chipInsets = EdgeInsets.fromLTRB(
        safe.left + 4, safe.top + 4, safe.right + 4, safe.bottom + 4);

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

        final shown = [
          for (final (index, item) in items.indexed)
            if (item.box != null)
              (
                item: item,
                rect: toViewport(item.box!),
                delay: Duration(milliseconds: 80 * index),
              ),
        ];

        return Stack(
          children: [
            for (final d in shown)
              Positioned.fromRect(
                key: ValueKey('scan-box-${d.item.id}'),
                rect: d.rect,
                child: _PopIn(
                  delay: d.delay,
                  child: _DetectionBox(
                      item: d.item, onTap: () => onTapItem(d.item)),
                ),
              ),
            Positioned.fill(
              child: CustomMultiChildLayout(
                delegate: _ChipsDelegate(
                  boxes: [for (final d in shown) (d.item.id, d.rect)],
                  insets: chipInsets,
                ),
                children: [
                  for (final d in shown) ...[
                    LayoutId(
                      key: labelKey(d.item.id),
                      id: _ChipsDelegate.labelId(d.item.id),
                      child: _PopIn(
                        delay: d.delay,
                        child: _NameChip(
                            item: d.item, onTap: () => onTapItem(d.item)),
                      ),
                    ),
                    LayoutId(
                      key: badgeKey(d.item.id),
                      id: _ChipsDelegate.badgeId(d.item.id),
                      child: _PopIn(
                        delay: d.delay,
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                              child: VeganBadge(isVegan: d.item.isVegan)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

Color _boxColor(DetectedIngredient item) => !item.confirmed
    ? const Color(0xFFF59E0B)
    : item.isVegan
        ? AppColors.sprout500
        : VeganBadge.nonVeganOnDark;

String _displayName(DetectedIngredient item) =>
    item.confirmed ? item.name : '${item.name}?';

/// Fades and grows in, [delay] after the previous detection.
class _PopIn extends StatelessWidget {
  const _PopIn({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240) + delay,
      curve: Interval(
        reduceMotion ? 0 : delay.inMilliseconds / (240 + delay.inMilliseconds),
        1,
        curve: Curves.easeOutBack,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0).toDouble(),
        child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
      ),
      child: child,
    );
  }
}

/// The box itself: solid for confident detections, dashed amber when it
/// still needs confirming. Carries the detection's semantics.
class _DetectionBox extends StatelessWidget {
  const _DetectionBox({required this.item, required this.onTap});

  final DetectedIngredient item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final confident = item.confirmed;
    final color = _boxColor(item);
    final vegan = item.isVegan ? 'Thuần chay' : 'Không thuần chay';
    final percent = '${(item.confidence * 100).round()}%';
    final label = _displayName(item);
    return Semantics(
      button: true,
      label: item.userVerified
          ? '$label, đã xác nhận, $vegan'
          : confident
              ? '$label, độ tin cậy $percent, $vegan'
              : 'Cần xác nhận: $label, độ tin cậy $percent, $vegan',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: confident
            ? DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
              )
            : DashedBorder(
                color: color,
                child: const DecoratedBox(
                  decoration: BoxDecoration(color: Color(0x14F59E0B)),
                ),
              ),
      ),
    );
  }
}

/// "Cà rốt 91%" (or "Rau chân vịt? 58%", or a check once the user confirmed
/// it), in the box colour.
class _NameChip extends StatelessWidget {
  const _NameChip({required this.item, required this.onTap});

  final DetectedIngredient item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const chipText = Color(0xFF111827);
    return ExcludeSemantics(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
              color: _boxColor(item), borderRadius: BorderRadius.circular(6)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _displayName(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: chipText,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (item.userVerified)
                const Icon(Icons.check_rounded, size: 14, color: chipText)
              else
                Text('${(item.confidence * 100).round()}%',
                    style: AppTypography.mono(
                        size: 11, weight: FontWeight.w700, color: chipText)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Measures every chip, then positions them all with [layoutDetectionChips].
class _ChipsDelegate extends MultiChildLayoutDelegate {
  _ChipsDelegate({required this.boxes, required this.insets});

  final List<(String, Rect)> boxes;
  final EdgeInsets insets;

  static String labelId(String id) => 'label:$id';
  static String badgeId(String id) => 'badge:$id';

  @override
  void performLayout(Size size) {
    final bounds = insets.deflateRect(Offset.zero & size);
    final loose = BoxConstraints.loose(
        Size(math.max(0.0, bounds.width), math.max(0.0, bounds.height)));
    final requests = [
      for (final (id, box) in boxes)
        DetectionChips(
          box: box,
          label: layoutChild(labelId(id), loose),
          badge: layoutChild(badgeId(id), loose),
        ),
    ];
    final placed = layoutDetectionChips(requests, bounds: bounds);
    for (final (i, (id, _)) in boxes.indexed) {
      positionChild(labelId(id), placed[i].label.topLeft);
      positionChild(badgeId(id), placed[i].badge.topLeft);
    }
  }

  // Records compare by value, so unchanged boxes skip the relayout.
  @override
  bool shouldRelayout(_ChipsDelegate oldDelegate) =>
      insets != oldDelegate.insets || !listEquals(boxes, oldDelegate.boxes);
}

/// One detection for [layoutDetectionChips]: its box in viewport space and
/// the measured sizes of its name chip and vegan badge.
class DetectionChips {
  const DetectionChips(
      {required this.box, required this.label, required this.badge});

  final Rect box;
  final Size label;
  final Size badge;
}

/// Where the name chip and the vegan badge of one detection go.
class DetectionChipPlacement {
  const DetectionChipPlacement({required this.label, required this.badge});

  final Rect label;
  final Rect badge;
}

/// Collision-aware placement of the detection chips over the preview.
///
/// Name chips sit on their box's top edge like a tab (left end, then right
/// end), else inside the box's top-left corner, else under the box. Badges
/// go inside the box's bottom-right corner when they fit (then bottom-left,
/// then centred on the bottom edge for narrow boxes), else under or above
/// the box. A spot is used only if it keeps clear of every chip placed so
/// far and of the other boxes; failing that, each spot is nudged up and down
/// a little, and only then is a spot that merely avoids other chips taken.
/// Names are placed before badges, top to bottom. Every chip is clamped
/// inside [bounds], so chips of boxes cropped by the preview stay visible.
List<DetectionChipPlacement> layoutDetectionChips(
  List<DetectionChips> items, {
  required Rect bounds,
}) {
  const inset = 4.0; // badge ↔ box edge
  const clearance = 2.0; // chip ↔ other chips and boxes
  const nudgeStep = 4.0;
  const nudgeSteps = 8;

  Rect clamp(Rect r) {
    final maxLeft = math.max(bounds.left, bounds.right - r.width);
    final maxTop = math.max(bounds.top, bounds.bottom - r.height);
    return Rect.fromLTWH(r.left.clamp(bounds.left, maxLeft).toDouble(),
        r.top.clamp(bounds.top, maxTop).toDouble(), r.width, r.height);
  }

  // The part of each box the user can see.
  final visible = [
    for (final i in items)
      i.box.overlaps(bounds) ? i.box.intersect(bounds) : clamp(i.box),
  ];
  final placed = <Rect>[];

  bool clearOf(Iterable<Rect> others, Rect r) =>
      others.every((o) => !o.inflate(clearance).overlaps(r));

  Rect place(int owner, Size size, List<Offset> spots) {
    final rects = [for (final s in spots) clamp(s & size)];
    final otherBoxes = [
      for (final (i, b) in visible.indexed)
        if (i != owner) b
    ];
    bool free(Rect r, {required bool avoidBoxes}) =>
        clearOf(placed, r) && (!avoidBoxes || clearOf(otherBoxes, r));

    for (final avoidBoxes in const [true, false]) {
      for (final r in rects) {
        if (free(r, avoidBoxes: avoidBoxes)) return r;
      }
      for (final r in rects) {
        for (var k = 1; k <= nudgeSteps; k++) {
          for (final dy in [-k * nudgeStep, k * nudgeStep]) {
            final moved = clamp(r.shift(Offset(0, dy)));
            if (free(moved, avoidBoxes: avoidBoxes)) return moved;
          }
        }
      }
    }
    return rects.first;
  }

  final order = List.generate(items.length, (i) => i)
    ..sort((a, b) {
      final byTop = visible[a].top.compareTo(visible[b].top);
      return byTop != 0 ? byTop : visible[a].left.compareTo(visible[b].left);
    });

  final labels = List<Rect>.filled(items.length, Rect.zero);
  for (final i in order) {
    final v = visible[i];
    final s = items[i].label;
    labels[i] = place(i, s, [
      Offset(v.left, v.top - s.height),
      Offset(v.right - s.width, v.top - s.height),
      if (v.width >= s.width + 2 * inset && v.height >= s.height + 2 * inset)
        Offset(v.left + inset, v.top + inset),
      Offset(v.left, v.bottom + inset),
    ]);
    placed.add(labels[i]);
  }

  final badges = List<Rect>.filled(items.length, Rect.zero);
  for (final i in order) {
    final v = visible[i];
    final b = items[i].badge;
    final fitsHeight = v.height >= b.height + 2 * inset;
    final fitsWidth = v.width >= b.width + 2 * inset;
    final insideTop = v.bottom - inset - b.height;
    badges[i] = place(i, b, [
      if (fitsHeight && fitsWidth) ...[
        Offset(v.right - inset - b.width, insideTop),
        Offset(v.left + inset, insideTop),
      ],
      if (fitsHeight) Offset(v.center.dx - b.width / 2, insideTop),
      Offset(v.right - b.width, v.bottom + inset),
      Offset(v.left, v.bottom + inset),
      Offset(v.right - b.width, v.top - inset - b.height),
    ]);
    placed.add(badges[i]);
  }

  return [
    for (var i = 0; i < items.length; i++)
      DetectionChipPlacement(label: labels[i], badge: badges[i]),
  ];
}

/// "✓ Thuần chay" / "✕ Không thuần chay" pill: icon and words, never colour
/// alone. [onDark] on the camera, otherwise in the tray.
class VeganBadge extends StatelessWidget {
  const VeganBadge({super.key, required this.isVegan, this.onDark = true});

  final bool isVegan;
  final bool onDark;

  /// Box and icon colour of non-vegan items over the camera.
  static const nonVeganOnDark = Color(0xFFF87171);

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    final Color iconColor;
    if (onDark) {
      background = const Color(0x99000000);
      foreground = isVegan ? AppColors.sprout200 : const Color(0xFFFECACA);
      iconColor = isVegan ? AppColors.sprout400 : nonVeganOnDark;
    } else if (isVegan) {
      background = context.vl.successContainer;
      foreground = iconColor = context.vl.onSuccessContainer;
    } else {
      background = context.colors.errorContainer;
      foreground = iconColor = context.colors.onErrorContainer;
    }

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isVegan ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 12, color: iconColor),
          const SizedBox(width: 4),
          Text(isVegan ? 'Thuần chay' : 'Không thuần chay',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: foreground)),
        ],
      ),
    );
  }
}
