// lib/features/community/presentation/widgets/feed_filter_chips.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/entities/post.dart';

/// Tất cả · Công thức · Video · Thảo luận. Scrolls sideways when the labels
/// don't fit (narrow phones, large text) instead of cutting them off.
class FeedFilterChips extends StatelessWidget {
  const FeedFilterChips(
      {super.key, required this.selected, required this.onSelected});

  /// `null` = Tất cả.
  final PostType? selected;
  final ValueChanged<PostType?> onSelected;

  static const _options = <(PostType?, String)>[
    (null, 'Tất cả'),
    (PostType.recipe, 'Công thức'),
    (PostType.video, 'Video'),
    (PostType.discussion, 'Thảo luận'),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // A chip with unbounded width sizes its label from cached text
        // metrics, which go stale once Google Fonts finishes loading
        // ("Công thứ", "Vide"). A finite max width makes it lay the label out
        // again with the real font.
        final available = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final maxChipWidth = math.max(0.0, available - 32);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final (i, (type, label)) in _options.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxChipWidth),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: selected == type,
                    onSelected: (_) => onSelected(type),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
