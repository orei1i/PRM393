// lib/features/community/domain/entities/post.dart
import 'dart:math' as math;

import '../../../../core/models/author_summary.dart';
import '../../../video/domain/entities/video_recipe.dart';

enum PostType {
  recipe('recipe', 'Công thức'),
  video('video', 'Video'),
  discussion('discussion', 'Thảo luận');

  const PostType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static PostType fromApi(String? value) =>
      values.firstWhere((t) => t.apiValue == value,
          orElse: () => PostType.discussion);
}

/// Reasons map 1:1 to the admin moderation categories on the web console.
enum ReportReason {
  healthMisinformation('health_misinformation', 'Thông tin sức khoẻ sai lệch'),
  notVegan('not_vegan', 'Không thuần chay'),
  spamPromo('spam_promo', 'Spam / quảng cáo'),
  harassment('harassment', 'Ngôn từ xúc phạm');

  const ReportReason(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class Post {
  const Post({
    required this.id,
    required this.type,
    required this.author,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.coverSeed,
    this.tags = const [],
    this.imageUrl,
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedByMe = false,
    this.savedByMe = false,
    this.isPinned = false,
    this.videoId,
    this.videoDurationSeconds,
    this.videoStatus,
  });

  final String id;
  final PostType type;
  final AuthorSummary author;
  final String title;
  final String body;
  final DateTime createdAt;
  final String coverSeed;

  /// Diet tag ids (`high_protein`, `quick`…) — labels via `dietTagLabel`.
  final List<String> tags;
  final String? imageUrl;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final bool savedByMe;

  /// Pinned by an admin from the web console.
  final bool isPinned;

  final String? videoId;
  final int? videoDurationSeconds;
  final VideoAiStatus? videoStatus;

  bool get hasCover => type != PostType.discussion || imageUrl != null;

  Post toggledLike() => copyWith(
        likedByMe: !likedByMe,
        likeCount: math.max(0, likeCount + (likedByMe ? -1 : 1)),
      );

  Post toggledSave() => copyWith(savedByMe: !savedByMe);

  Post copyWith({
    int? likeCount,
    int? commentCount,
    bool? likedByMe,
    bool? savedByMe,
    VideoAiStatus? videoStatus,
  }) {
    return Post(
      id: id,
      type: type,
      author: author,
      title: title,
      body: body,
      createdAt: createdAt,
      coverSeed: coverSeed,
      tags: tags,
      imageUrl: imageUrl,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      likedByMe: likedByMe ?? this.likedByMe,
      savedByMe: savedByMe ?? this.savedByMe,
      isPinned: isPinned,
      videoId: videoId,
      videoDurationSeconds: videoDurationSeconds,
      videoStatus: videoStatus ?? this.videoStatus,
    );
  }
}

class Comment {
  const Comment({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    this.pending = false,
  });

  final String id;
  final AuthorSummary author;
  final String text;
  final DateTime createdAt;

  /// Optimistically added, not yet confirmed by the server.
  final bool pending;
}

class FeedPage {
  const FeedPage({required this.items, this.nextCursor});

  final List<Post> items;
  final String? nextCursor;
}
