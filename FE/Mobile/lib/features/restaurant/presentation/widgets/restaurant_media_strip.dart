// lib/features/restaurant/presentation/widgets/restaurant_media_strip.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../video/presentation/widgets/video_player_view.dart';
import '../../domain/entities/restaurant.dart';

/// "Ảnh & video" of a restaurant: a horizontal strip of photos and the intro
/// video; tapping one opens it full screen. Photos draw over an illustrated
/// cover, so a missing file never shows as broken.
class RestaurantMediaStrip extends StatelessWidget {
  const RestaurantMediaStrip({super.key, required this.media});

  final List<RestaurantMedia> media;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: media.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final m = media[i];
          return Semantics(
            button: true,
            label: m.isVideo ? 'Video giới thiệu quán' : 'Ảnh ${i + 1}',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => RestaurantMediaViewer(media: m),
              )),
              child: SizedBox(
                width: 128,
                child: MediaThumb(media: m),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One photo (or the video with a play badge) as a rounded cover.
class MediaThumb extends StatelessWidget {
  const MediaThumb({super.key, required this.media, this.height = 96});

  final RestaurantMedia media;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FoodCover(
      seed: media.url,
      height: height,
      imageUrl: media.isVideo ? null : media.url,
      borderRadius: BorderRadius.circular(12),
      child: media.isVideo
          ? const Center(
              child: CircleAvatar(
                radius: 18,
                backgroundColor: Color(0x99000000),
                child: Icon(Icons.play_arrow_rounded, color: Colors.white),
              ),
            )
          : null,
    );
  }
}

/// Full-screen photo (pinch to zoom) or the intro video.
class RestaurantMediaViewer extends StatelessWidget {
  const RestaurantMediaViewer({super.key, required this.media});

  final RestaurantMedia media;

  @override
  Widget build(BuildContext context) {
    final by = media.uploadedByName ?? 'Ban quản trị VeganLife';
    final when =
        media.createdAt == null ? null : relativeTime(media.createdAt!);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(media.isVideo ? 'Video giới thiệu' : 'Ảnh của quán'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: media.isVideo
                  ? VideoPlayerView(url: media.url, coverSeed: media.url)
                  : InteractiveViewer(
                      child: FoodCover(
                        seed: media.url,
                        imageUrl: media.url,
                        aspectRatio: 4 / 3,
                      ),
                    ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                when == null ? 'Đăng bởi $by' : 'Đăng bởi $by · $when',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
