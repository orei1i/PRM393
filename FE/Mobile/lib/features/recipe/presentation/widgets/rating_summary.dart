// lib/features/recipe/presentation/widgets/rating_summary.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/recipe_review.dart';

/// Five stars for [rating] (halves for an average).
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, this.size = 16});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = context.vl.caution;
    return Semantics(
      label: '${formatDecimal(rating)} trên 5 sao',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              rating >= i
                  ? Icons.star_rounded
                  : rating >= i - 0.5
                      ? Icons.star_half_rounded
                      : Icons.star_border_rounded,
              size: size,
              color: color,
            ),
        ],
      ),
    );
  }
}

/// "4,6" + stars + "5 đánh giá" and the 5 → 1 distribution; "Chưa có đánh
/// giá" with an invitation when nobody rated the recipe yet.
class RatingSummaryCard extends StatelessWidget {
  const RatingSummaryCard({super.key, required this.summary});

  final RatingSummary summary;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    if (summary.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chưa có đánh giá',
              style: context.textStyles.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Hãy là người đầu tiên chia sẻ cảm nhận về món này.',
              style: context.textStyles.bodyMedium?.copyWith(color: vl.muted)),
        ],
      );
    }
    final total = summary.count;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Text(summary.averageLabel,
                style: context.textStyles.displaySmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            StarRow(rating: summary.average ?? 0),
            const SizedBox(height: 4),
            Text('${formatInt(total)} đánh giá',
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
          ],
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            children: [
              for (var s = 5; s >= 1; s--)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Semantics(
                    label: '$s sao: ${summary.countOf(s)} đánh giá',
                    excludeSemantics: true,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          child: Text('$s',
                              style: context.textStyles.bodySmall
                                  ?.copyWith(color: vl.muted)),
                        ),
                        Icon(Icons.star_rounded, size: 12, color: vl.caution),
                        const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: summary.countOf(s) / total,
                              minHeight: 6,
                              color: vl.caution,
                              backgroundColor: context.colors.surfaceContainer,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 28,
                          child: Text('${summary.countOf(s)}',
                              textAlign: TextAlign.end,
                              style: context.textStyles.bodySmall
                                  ?.copyWith(color: vl.muted)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
