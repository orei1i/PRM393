// lib/features/reels/domain/reel.dart
import '../../community/domain/entities/post.dart';

/// A short vertical clip: a `posts` row with `media_type = Video`, played
/// full screen. Like, save and comment go through the post.
class Reel {
  const Reel({required this.post, this.videoUrl, this.durationSeconds});

  final Post post;

  /// Playable file (`posts.media_url`, or the linked video's file).
  final String? videoUrl;

  /// `posts.duration_seconds` (proposed column), else the video's length.
  final int? durationSeconds;

  String get id => post.id;

  /// "Xem công thức": the AI pipeline extracted a recipe from the video
  /// (Công thức posts only).
  bool get hasRecipe => post.hasAiRecipe;

  Reel withPost(Post updated) =>
      Reel(post: updated, videoUrl: videoUrl, durationSeconds: durationSeconds);
}
