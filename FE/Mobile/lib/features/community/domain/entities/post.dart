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

/// `posts.status`. New and edited posts are published unless the AI
/// pre-screen flags them; flagged ones wait for an admin decision.
enum PostStatus {
  pending('Pending', 'Chờ duyệt'),
  published('Published', 'Đã đăng'),
  rejected('Rejected', 'Bị từ chối');

  const PostStatus(this.apiValue, this.label);
  final String apiValue;
  final String label;

  /// Case-insensitive; a missing or unknown value is a legacy, live post.
  static PostStatus fromApi(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    for (final s in values) {
      if (s.apiValue.toLowerCase() == raw) return s;
    }
    return published;
  }
}

/// `posts.media_type`. The FE [PostType] stays the category shown in the UI.
enum PostMediaType {
  text('Text'),
  image('Image'),
  video('Video');

  const PostMediaType(this.apiValue);
  final String apiValue;

  static PostMediaType? tryParse(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    for (final m in values) {
      if (m.apiValue.toLowerCase() == raw) return m;
    }
    return null;
  }

  /// What the server would store when the field is missing.
  static PostMediaType derive({required String type, String? imageUrl}) {
    if (type == PostType.video.apiValue) return video;
    if (imageUrl != null) return image;
    return text;
  }
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
    this.status = PostStatus.published,
    PostMediaType? mediaType,
    this.mediaUrl,
    this.rejectionReason,
    this.updatedAt,
  }) : _mediaType = mediaType;

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

  /// Only [PostStatus.published] posts reach the feed and search; the author
  /// still sees the others in "Nội dung của tôi".
  final PostStatus status;

  final PostMediaType? _mediaType;
  PostMediaType get mediaType =>
      _mediaType ??
      PostMediaType.derive(type: type.apiValue, imageUrl: imageUrl);

  /// Uploaded video / image URL, or the pasted video link.
  final String? mediaUrl;

  /// The admin's note when [status] is [PostStatus.rejected].
  final String? rejectionReason;
  final DateTime? updatedAt;

  bool get hasCover => type != PostType.discussion || imageUrl != null;

  bool get isPublished => status == PostStatus.published;
  bool get isPending => status == PostStatus.pending;
  bool get isRejected => status == PostStatus.rejected;

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
      status: status,
      mediaType: _mediaType,
      mediaUrl: mediaUrl,
      rejectionReason: rejectionReason,
      updatedAt: updatedAt,
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
    this.postId,
    this.updatedAt,
  });

  final String id;
  final AuthorSummary author;
  final String text;
  final DateTime createdAt;

  /// Optimistically added, not yet confirmed by the server.
  final bool pending;

  final String? postId;
  final DateTime? updatedAt;

  /// Shows "(đã sửa)".
  bool get isEdited => updatedAt != null;

  Comment copyWith({String? text, DateTime? updatedAt, bool? pending}) =>
      Comment(
        id: id,
        author: author,
        text: text ?? this.text,
        createdAt: createdAt,
        pending: pending ?? this.pending,
        postId: postId,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// One of the member's comments, listed under "Nội dung của tôi › Bình luận".
class MyComment {
  const MyComment({
    required this.id,
    required this.postId,
    required this.postTitle,
    required this.text,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String postId;
  final String postTitle;
  final String text;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get isEdited => updatedAt != null;
}

class FeedPage {
  const FeedPage({required this.items, this.nextCursor});

  final List<Post> items;
  final String? nextCursor;
}
