// lib/features/search/presentation/widgets/search_tiles.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../community/domain/entities/post.dart';
import '../../domain/entities/search_result.dart';

/// Compact full-width rows for search results (own widgets, so the feed's
/// `PostCard` can change freely). Lists separate rows with
/// [SearchRowDivider].
class SearchRowDivider extends StatelessWidget {
  const SearchRowDivider({super.key, this.indent = 16});

  final double indent;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: context.colors.surface,
        child: Divider(height: 1, indent: indent, color: context.vl.border),
      );
}

/// "Công thức" row: dish name, kcal, vegan tag. [dense] drops the side
/// padding (inside an already padded list).
class SearchRecipeTile extends StatelessWidget {
  const SearchRecipeTile(
      {super.key,
      required this.recipe,
      required this.onTap,
      this.dense = false});

  final RecipeSummary recipe;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (recipe.calories != null) '${formatInt(recipe.calories!)} kcal',
      if (recipe.isVegan) 'Thuần chay',
    ].join(' · ');
    return Material(
      color: context.colors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: dense
              ? const EdgeInsets.symmetric(vertical: 8)
              : const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: dense ? 40 : 48,
                height: dense ? 40 : 48,
                decoration: BoxDecoration(
                  color: context.colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.rice_bowl_rounded,
                    color: context.colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(recipe.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(meta,
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: context.vl.muted)),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.vl.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Bài viết" / "Video" row: thumbnail, title, category · author · time.
class SearchPostTile extends StatelessWidget {
  const SearchPostTile({super.key, required this.post, required this.onTap});

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = [
      post.hasVideo ? '${post.type.label} · Video' : post.type.label,
      post.author.name,
      relativeTime(post.createdAt),
    ].join(' · ');
    return Material(
      color: context.colors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 104,
                child: post.hasCover
                    ? FoodCover(
                        seed: post.coverSeed,
                        imageUrl: post.imageSrc,
                        aspectRatio: 4 / 3,
                        borderRadius: BorderRadius.circular(10),
                        child: post.hasVideo
                            ? _VideoBadge(seconds: post.videoDurationSeconds)
                            : null,
                      )
                    : AspectRatio(
                        aspectRatio: 4 / 3,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.forum_outlined,
                              color: context.vl.muted),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: context.vl.muted)),
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

/// Card in the horizontal "Video & bài viết liên quan" row.
class RelatedPostCard extends StatelessWidget {
  const RelatedPostCard({super.key, required this.post, required this.onTap});

  static const width = 200.0;

  final Post post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: VLCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FoodCover(
              seed: post.coverSeed,
              imageUrl: post.imageSrc,
              aspectRatio: 16 / 9,
              child: post.hasVideo
                  ? _VideoBadge(seconds: post.videoDurationSeconds)
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleSmall),
                  const SizedBox(height: 4),
                  Text('${post.type.label} · ${post.author.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: context.vl.muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Play mark + duration over a video thumbnail.
class _VideoBadge extends StatelessWidget {
  const _VideoBadge({this.seconds});

  final int? seconds;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Center(
          child: Icon(Icons.play_circle_fill_rounded,
              color: Colors.white, size: 32),
        ),
        if (seconds != null)
          Positioned(
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(formatDuration(seconds!),
                  style: context.textStyles.labelSmall
                      ?.copyWith(color: Colors.white)),
            ),
          ),
      ],
    );
  }
}

/// Loading rows for the first search.
class SearchResultsSkeleton extends StatelessWidget {
  const SearchResultsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < 6; i++)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 104, height: 78, radius: 10),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(height: 16),
                        SizedBox(height: 8),
                        SkeletonBox(width: 160, height: 12),
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
