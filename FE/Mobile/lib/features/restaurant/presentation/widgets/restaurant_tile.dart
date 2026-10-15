// lib/features/restaurant/presentation/widgets/restaurant_tile.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../domain/entities/restaurant.dart';
import '../../domain/geo.dart';

/// Full-width restaurant row (nearby list, search results, suggestions):
/// thumbnail · name · address · certification · distance · rating.
/// Lists separate rows with [RestaurantTileDivider].
class RestaurantTile extends StatelessWidget {
  const RestaurantTile(
      {super.key, required this.restaurant, required this.onTap});

  final Restaurant restaurant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = restaurant;
    return Material(
      color: context.colors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RestaurantThumb(seed: r.id),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: context.vl.muted),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        CertificationTag(certified: r.isVeganCertified),
                        DistanceLabel(restaurant: r),
                        RatingLabel(
                            average: r.averageRating, count: r.reviewCount),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hairline between two [RestaurantTile]s, aligned with the text column.
class RestaurantTileDivider extends StatelessWidget {
  const RestaurantTileDivider({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: context.colors.surface,
        child: Divider(height: 1, indent: 92, color: context.vl.border),
      );
}

/// Illustrated square with a storefront mark (no photos in the DB yet).
class RestaurantThumb extends StatelessWidget {
  const RestaurantThumb({super.key, required this.seed, this.size = 64});

  final String seed;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: FoodCover(
        seed: seed,
        height: size,
        borderRadius: BorderRadius.circular(12),
        child: Center(
          child: Icon(Icons.storefront_rounded,
              color: Colors.white, size: size * 0.42),
        ),
      ),
    );
  }
}

/// "Chứng nhận chay" (verified by the admin team) or "Chưa chứng nhận".
/// Like `VLTag`, but the label wraps instead of overflowing with large text.
class CertificationTag extends StatelessWidget {
  const CertificationTag({super.key, required this.certified});

  final bool certified;

  @override
  Widget build(BuildContext context) {
    final bg = certified
        ? context.vl.successContainer
        : context.colors.surfaceContainer;
    final fg = certified
        ? context.vl.onSuccessContainer
        : context.colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (certified) ...[
            Icon(Icons.verified_rounded, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              certified ? 'Chứng nhận chay' : 'Chưa chứng nhận',
              style: context.textStyles.labelMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// "850 m" / "1,2 km", or "Chưa có vị trí" without coordinates.
class DistanceLabel extends StatelessWidget {
  const DistanceLabel({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    final km = restaurant.hasLocation ? restaurant.distanceKm : null;
    final style =
        context.textStyles.labelMedium?.copyWith(color: context.vl.muted);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(km == null ? Icons.location_off_outlined : Icons.near_me_outlined,
            size: 16, color: context.vl.muted),
        const SizedBox(width: 4),
        Flexible(child: Text(formatDistance(km), style: style)),
      ],
    );
  }
}

/// "★ 4,6 (38)", or "Chưa có đánh giá".
class RatingLabel extends StatelessWidget {
  const RatingLabel({super.key, required this.average, required this.count});

  final double? average;
  final int count;

  @override
  Widget build(BuildContext context) {
    final style =
        context.textStyles.labelMedium?.copyWith(color: context.vl.muted);
    final avg = average;
    if (avg == null || count == 0) {
      return Text('Chưa có đánh giá', style: style);
    }
    return Semantics(
      label: 'Đánh giá ${formatDecimal(avg)} trên 5, $count lượt',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 16, color: context.vl.caution),
          const SizedBox(width: 2),
          Flexible(
            child: Text('${formatDecimal(avg)} ($count)',
                style: style?.copyWith(color: context.colors.onSurface)),
          ),
        ],
      ),
    );
  }
}

/// Read-only stars for a 1…5 rating.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, this.size = 16});

  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star_rounded
                : rating >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            size: size,
            color: context.vl.caution,
          ),
      ],
    );
  }
}

/// Loading rows shaped like [RestaurantTile].
class RestaurantListSkeleton extends StatelessWidget {
  const RestaurantListSkeleton({super.key, this.rows = 6});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < rows; i++)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 64, height: 64, radius: 12),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 180, height: 16),
                        SizedBox(height: 8),
                        SkeletonBox(height: 12),
                        SizedBox(height: 10),
                        SkeletonBox(width: 140, height: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
