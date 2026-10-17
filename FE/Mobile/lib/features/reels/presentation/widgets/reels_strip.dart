// lib/features/reels/presentation/widgets/reels_strip.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../domain/reel.dart';
import '../controllers/reels_controller.dart';
import '../screens/reels_player_screen.dart';

/// "Bếp nhanh" (short vertical videos) near the top of Trang chủ: 9:16 thumbnails with author and
/// length; a tap opens the full-screen player at that clip (no "Xem tất
/// cả": swiping in the player goes through them all). Hidden when there are
/// no reels; a failed load leaves a one-line retry.
class ReelsStrip extends ConsumerWidget {
  const ReelsStrip({super.key});

  static const double thumbWidth = 112;
  static const double thumbHeight = thumbWidth * 16 / 9;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reelsProvider);
    final reels = async.valueOrNull;
    if (reels == null) {
      if (async.hasError) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(
            children: [
              Icon(Icons.slow_motion_video_rounded,
                  size: 18, color: context.vl.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Chưa tải được Bếp nhanh.',
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: context.vl.muted)),
              ),
              TextButton(
                onPressed: () => ref.invalidate(reelsProvider),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        );
      }
      return const _StripSkeleton();
    }
    if (reels.isEmpty) return const SizedBox.shrink();

    void open(int index) => Navigator.of(context)
        .push(ReelsPlayerScreen.route(reels, initialIndex: index));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Icon(Icons.slow_motion_video_rounded,
                    size: 20, color: context.vl.ai),
                const SizedBox(width: 8),
                Expanded(
                  child:
                      Text('Bếp nhanh', style: context.textStyles.titleMedium),
                ),
              ],
            ),
          ),
          SizedBox(
            height: thumbHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: reels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) =>
                  _ReelThumb(reel: reels[i], onTap: () => open(i)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelThumb extends StatelessWidget {
  const _ReelThumb({required this.reel, required this.onTap});

  final Reel reel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final post = reel.post;
    final seconds = reel.durationSeconds;
    const shadow = [Shadow(blurRadius: 4)];
    return Semantics(
      button: true,
      label: 'Bếp nhanh của ${post.author.name}: ${post.title}',
      excludeSemantics: true,
      child: SizedBox(
        width: ReelsStrip.thumbWidth,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Material(
            color: Colors.black,
            child: InkWell(
              onTap: onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FoodCover(seed: post.coverSeed, imageUrl: post.imageUrl),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xB3000000)],
                        stops: [0.45, 1],
                      ),
                    ),
                  ),
                  const Center(
                    child: Icon(Icons.play_circle_fill_rounded,
                        size: 36, color: Colors.white70),
                  ),
                  if (seconds != null && seconds > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0x99000000),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(formatDuration(seconds),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              shadows: shadow),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          post.author.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              shadows: shadow),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StripSkeleton extends StatelessWidget {
  const _StripSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 80, height: 18),
            const SizedBox(height: 10),
            SizedBox(
              height: ReelsStrip.thumbHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 4,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, __) => const SkeletonBox(
                    width: ReelsStrip.thumbWidth,
                    height: ReelsStrip.thumbHeight,
                    radius: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
