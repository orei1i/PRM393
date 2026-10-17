// lib/features/community/domain/entities/post.dart
import 'dart:math' as math;

import '../../../../core/models/author_summary.dart';
import '../../../video/domain/entities/video_recipe.dart';

/// `posts.type`: only "Công thức" and "Hỏi đáp". A photo or a video is an
/// attachment ([PostMediaType]), not a category.
enum PostType {
  recipe('recipe', 'Công thức'),
  discussion('discussion', 'Hỏi đáp');

  const PostType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  /// Legacy wire value `video` reads as [recipe]; unknown values read as
  /// [discussion].
  static PostType fromApi(String? value) {
    if (value == 'video') return PostType.recipe;
    return values.firstWhere((t) => t.apiValue == value,
        orElse: () => PostType.discussion);
  }
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

/// `posts.media_type`: the one attachment a post may carry
/// (`posts.media_url`).
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

  /// What the server would store when the field is missing: the legacy
  /// `type: "video"` or a linked video is a video, an image URL an image.
  static PostMediaType derive(
      {required String type, String? imageUrl, String? videoId}) {
    if (type == 'video' || videoId != null) return video;
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

/// The restaurant a post checks in at (`posts.restaurant_id`, organic, not
/// paid): "— tại Quán Chay An Lạc" plus a chip that opens the restaurant.
class TaggedRestaurant {
  const TaggedRestaurant({
    required this.id,
    required this.name,
    this.district,
    this.isCertified = false,
  });

  final String id;
  final String name;

  /// "Q.1", "Q. Bình Thạnh"…
  final String? district;
  final bool isCertified;

  /// "Q.1" from "12 Nguyễn Thị Minh Khai, P. Đa Kao, Q.1, TP.HCM": the part
  /// naming the district ("Q.", "Quận", "Huyện", "TP. Thủ Đức"), else the
  /// part before the city.
  static String? districtOf(String address) {
    final parts = address
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    for (final p in parts.reversed) {
      final lower = p.toLowerCase();
      if (lower.startsWith('q.') ||
          lower.startsWith('quận') ||
          lower.startsWith('huyện') ||
          lower.startsWith('h.') ||
          lower.startsWith('tp. thủ đức')) {
        return p;
      }
    }
    return parts.length >= 2 ? parts[parts.length - 2] : null;
  }
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
    this.restaurant,
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

  /// Every comment, replies included.
  final int commentCount;
  final bool likedByMe;
  final bool savedByMe;

  /// Pinned by an admin from the web console.
  final bool isPinned;

  /// The AI recipe of an attached video (Công thức + video only).
  final String? videoId;
  final int? videoDurationSeconds;
  final VideoAiStatus? videoStatus;

  /// Only [PostStatus.published] posts reach the feed and search; the author
  /// still sees the others in "Nội dung của tôi".
  final PostStatus status;

  final PostMediaType? _mediaType;
  PostMediaType get mediaType =>
      _mediaType ??
      PostMediaType.derive(
          type: type.apiValue, imageUrl: imageUrl, videoId: videoId);

  /// Uploaded video / image URL.
  final String? mediaUrl;

  /// The admin's note when [status] is [PostStatus.rejected].
  final String? rejectionReason;
  final DateTime? updatedAt;

  /// "— tại {quán}"; `null` when the post tags no restaurant.
  final TaggedRestaurant? restaurant;

  bool get hasVideo => mediaType == PostMediaType.video;

  /// The attached photo, if any.
  String? get imageSrc =>
      imageUrl ?? (mediaType == PostMediaType.image ? mediaUrl : null);

  /// "Xem công thức": the AI pipeline extracted a recipe from the video.
  bool get hasAiRecipe => videoId != null && videoStatus == VideoAiStatus.ready;

  /// Recipes get an illustrated cover; Q&A only shows a real attachment.
  bool get hasCover => type == PostType.recipe || hasVideo || imageSrc != null;

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
      restaurant: restaurant,
    );
  }
}

/// A comment. Top-level comments carry [replyCount] and a preview of their
/// first [replies]; replies ([parentId] set) are one level deep.
class Comment {
  const Comment({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    this.pending = false,
    this.postId,
    this.parentId,
    this.updatedAt,
    this.replyCount = 0,
    this.replies = const [],
  });

  final String id;
  final AuthorSummary author;
  final String text;
  final DateTime createdAt;

  /// Optimistically added, not yet confirmed by the server.
  final bool pending;

  final String? postId;

  /// The top-level comment this one answers; `null` for a top-level one.
  final String? parentId;
  final DateTime? updatedAt;

  /// Top-level only: every reply, loaded or not.
  final int replyCount;

  /// Top-level only: the first replies, oldest first (the server previews 2).
  final List<Comment> replies;

  bool get isReply => parentId != null;

  /// Shows "(đã sửa)".
  bool get isEdited => updatedAt != null;

  Comment copyWith({
    String? text,
    DateTime? updatedAt,
    bool? pending,
    int? replyCount,
    List<Comment>? replies,
  }) =>
      Comment(
        id: id,
        author: author,
        text: text ?? this.text,
        createdAt: createdAt,
        pending: pending ?? this.pending,
        postId: postId,
        parentId: parentId,
        updatedAt: updatedAt ?? this.updatedAt,
        replyCount: replyCount ?? this.replyCount,
        replies: replies ?? this.replies,
      );
}

/// One page of comments (newest first) or of replies (oldest first).
class CommentPage {
  const CommentPage({required this.items, this.nextCursor});

  final List<Comment> items;
  final String? nextCursor;
}

/// One of the member's comments, listed under "Nội dung của tôi › Bình luận".
class MyComment {
  const MyComment({
    required this.id,
    required this.postId,
    required this.postTitle,
    required this.text,
    required this.createdAt,
    this.parentId,
    this.updatedAt,
  });

  final String id;
  final String postId;
  final String postTitle;
  final String text;
  final DateTime createdAt;

  /// Set when the comment is a reply.
  final String? parentId;
  final DateTime? updatedAt;

  bool get isEdited => updatedAt != null;
}

class FeedPage {
  const FeedPage({required this.items, this.nextCursor});

  final List<Post> items;
  final String? nextCursor;
}
