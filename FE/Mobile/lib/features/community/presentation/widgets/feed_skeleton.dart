// lib/features/community/presentation/widgets/feed_skeleton.dart
import 'package:flutter/material.dart';

import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/vl_card.dart';

class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key, this.count = 3});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: VLCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        SkeletonBox(width: 38, height: 38, radius: 19),
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
                    const SizedBox(height: 14),
                    const SkeletonBox(width: 240, height: 16),
                    const SizedBox(height: 8),
                    const SkeletonBox(height: 12),
                    const SizedBox(height: 6),
                    const SkeletonBox(width: 200, height: 12),
                    if (i.isEven) ...[
                      const SizedBox(height: 12),
                      const AspectRatio(
                          aspectRatio: 16 / 9,
                          child:
                              SkeletonBox(height: double.infinity, radius: 14)),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
