// lib/features/reels/presentation/controllers/reels_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/session/session_controller.dart';
import '../../../community/presentation/controllers/feed_controller.dart';
import '../../data/reels_api_service.dart';
import '../../domain/reel.dart';

/// The "Bếp nhanh" strip on Trang chủ. Refetched on sign-in/out (likedByMe is
/// per user) and after the member likes, saves or comments anywhere.
final reelsProvider = FutureProvider<List<Reel>>((ref) async {
  ref
    ..watch(sessionControllerProvider.select((s) => s.accessToken))
    ..watch(communityRevisionProvider);
  final dtos = await ref.watch(reelsApiProvider).getReels();
  return [
    for (final d in dtos)
      if (d.toEntity() case final reel when reel.post.isPublished) reel,
  ];
});

typedef ReelVideoFactory = VideoPlayerController Function(String url);

/// Creates the player for a reel. Widget tests swap it for one that fails
/// fast (no video plugin there).
final reelVideoFactoryProvider = Provider<ReelVideoFactory>(
    (ref) => (url) => VideoPlayerController.networkUrl(Uri.parse(url)));
