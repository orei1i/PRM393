// lib/features/community/presentation/widgets/feed_skeleton.dart
import 'package:flutter/material.dart';

import '../../../../core/widgets/shimmer.dart';
import 'post_card.dart';

/// Placeholder for full-width posts while the feed loads.
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < count; i++) ...[
          const PostListGap(),
          Shimmer(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        SkeletonBox(width: 40, height: 40, radius: 20),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(width: 120, height: 12),
                            SizedBox(height: 6),
                            SkeletonBox(width: 80, height: 10),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox(width: 240, height: 16),
                        SizedBox(height: 8),
                        SkeletonBox(height: 12),
                        SizedBox(height: 6),
                        SkeletonBox(width: 200, height: 12),
                      ],
                    ),
                  ),
                  if (i.isEven) ...[
                    const SizedBox(height: 12),
                    const AspectRatio(
                        aspectRatio: 16 / 9,
                        child: SkeletonBox(height: double.infinity, radius: 0)),
                  ],
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SkeletonBox(height: 28),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
