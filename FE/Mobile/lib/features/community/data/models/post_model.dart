// lib/features/community/data/models/post_model.dart
//
// GET /posts?type=recipe|discussion&mediaType=Video&cursor=…&limit=10
// { "items": [ { "id": "p_101", "type": "recipe",
//   "author": { "id": "u_1", "fullName": "…", "isVerifiedChef": false },
//   "title": "…", "body": "…", "tags": ["quick"], "coverSeed": "bun-rieu", "imageUrl": null,
//   "likeCount": 128, "commentCount": 14, "likedByMe": false, "savedByMe": true, "isPinned": false,
//   "createdAt": "2026-10-14T02:10:00Z",
//   "status": "Published", "mediaType": "Video", "mediaUrl": "https://…mp4",
//   "video": { "id": "vid_x", "durationSeconds": 724, "aiStatus": "ready" },
//   "restaurant": { "id": "r1", "name": "Quán Chay An Lạc", "district": "Q.1", "isCertified": true },
//   "rejectionReason": null, "updatedAt": null } ],
//   "nextCursor": "p_095" }
//
// `type` is `recipe` | `discussion`; the legacy `video` reads as `recipe`
// with `mediaType: Video`. `status` / `mediaType` follow posts.status /
// posts.media_type: missing `status` → Published (legacy); missing
// `mediaType` → derived. `video` (the AI recipe) only exists for
// Công thức + video. `restaurant` is the joined `posts.restaurant_id`
// (proposed column), `null` when the post tags no restaurant.
//
// POST /posts | PUT /posts/{id}
// { "type": "recipe", "title": "…", "body": "…", "tags": ["quick"],
//   "mediaType": "Text|Image|Video", "mediaUrl": "https://…" | null, "restaurantId": "r1" | null }
//
// Comments (table `comments` + proposed `parent_id`, top-level only):
// GET /posts/{id}/comments?cursor=&limit=10 → { "items": [CommentDto], "nextCursor": "10" | null }
//   newest first; each top-level comment previews its first 2 replies.
// GET /posts/{id}/comments/{commentId}/replies?cursor=&limit=20 → same page shape, oldest first.
// POST /posts/{id}/comments { "content": "…", "parentId": "c1" | null } → CommentDto
// PUT /posts/{id}/comments/{commentId} { "content": "…" } → CommentDto
// DELETE /posts/{id}/comments/{commentId} → 204 (a top-level comment takes its replies with it)
// CommentDto:
// { "id": "c1", "postId": "p1", "parentId": null, "author": {…}, "content": "…",
//   "createdAt": "…", "updatedAt": null, "replyCount": 3, "replies": [ /* first 2 CommentDto */ ] }
import '../../../../core/models/author_summary.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../video/domain/entities/video_recipe.dart';
import '../../domain/entities/post.dart';

/// `{ "id", "name", "district", "isCertified" }`.
class TaggedRestaurantDto {
  const TaggedRestaurantDto({
    required this.id,
    required this.name,
    this.district,
    this.isCertified = false,
  });

  static TaggedRestaurantDto? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    return TaggedRestaurantDto(
      id: id,
      name: json['name'] as String? ?? '',
      district: json['district'] as String?,
      isCertified:
          json['isCertified'] == true || json['isVeganCertified'] == true,
    );
  }

  factory TaggedRestaurantDto.fromEntity(TaggedRestaurant r) =>
      TaggedRestaurantDto(
          id: r.id,
          name: r.name,
          district: r.district,
          isCertified: r.isCertified);

  final String id;
  final String name;
  final String? district;
  final bool isCertified;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'district': district,
        'isCertified': isCertified,
      };

  TaggedRestaurant toEntity() => TaggedRestaurant(
      id: id, name: name, district: district, isCertified: isCertified);
}

class PostDto {
  const PostDto({
    required this.id,
    required this.type,
    required this.author,
    required this.title,
    required this.body,
    required this.createdAt,
    this.coverSeed,
    this.tags = const [],
    this.imageUrl,
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedByMe = false,
    this.savedByMe = false,
    this.isPinned = false,
    this.videoId,
    this.videoDurationSeconds,
    this.videoAiStatus,
    this.status = 'Published',
    this.mediaType,
    this.mediaUrl,
    this.rejectionReason,
    this.updatedAt,
    this.restaurant,
  });

  factory PostDto.fromJson(Map<String, dynamic> json) {
    final video = json['video'];
    final videoMap = video is Map<String, dynamic> ? video : null;
    final rawType = json['type'] as String? ?? 'discussion';
    final imageUrl = json['imageUrl'] as String?;
    final videoId = videoMap?['id']?.toString();
    return PostDto(
      id: json['id']?.toString() ?? '',
      type: PostType.fromApi(rawType).apiValue,
      author: AuthorSummary.fromJsonValue(json['author']),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? json['content'] as String? ?? '',
      createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
      coverSeed: json['coverSeed'] as String?,
      tags: readStringList(json['tags']),
      imageUrl: imageUrl,
      likeCount: readInt(json['likeCount']),
      commentCount: readInt(json['commentCount']),
      likedByMe: json['likedByMe'] == true,
      savedByMe: json['savedByMe'] == true,
      isPinned: json['isPinned'] == true,
      videoId: videoId,
      videoDurationSeconds:
          videoMap == null ? null : readInt(videoMap['durationSeconds']),
      videoAiStatus: videoMap?['aiStatus'] as String?,
      status: PostStatus.fromApi(json['status']).apiValue,
      mediaType: (PostMediaType.tryParse(json['mediaType']) ??
              PostMediaType.derive(
                  type: rawType, imageUrl: imageUrl, videoId: videoId))
          .apiValue,
      mediaUrl: json['mediaUrl'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
      updatedAt: readDateTime(json['updatedAt']),
      restaurant: TaggedRestaurantDto.tryParse(json['restaurant']),
    );
  }

  final String id;

  /// `recipe` | `discussion` (a legacy `video` is already mapped).
  final String type;
  final AuthorSummary author;
  final String title;
  final String body;
  final DateTime createdAt;
  final String? coverSeed;
  final List<String> tags;
  final String? imageUrl;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;
  final bool savedByMe;
  final bool isPinned;
  final String? videoId;
  final int? videoDurationSeconds;
  final String? videoAiStatus;

  /// `Pending` | `Published` | `Rejected`.
  final String status;

  /// `Text` | `Image` | `Video`; derived when the server omits it.
  final String? mediaType;
  final String? mediaUrl;
  final String? rejectionReason;
  final DateTime? updatedAt;
  final TaggedRestaurantDto? restaurant;

  bool get hasVideo => mediaType == PostMediaType.video.apiValue;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'author': author.toJson(),
        'title': title,
        'body': body,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'coverSeed': coverSeed,
        'tags': tags,
        'imageUrl': imageUrl,
        'likeCount': likeCount,
        'commentCount': commentCount,
        'likedByMe': likedByMe,
        'savedByMe': savedByMe,
        'isPinned': isPinned,
        if (videoId != null)
          'video': {
            'id': videoId,
            'durationSeconds': videoDurationSeconds,
            'aiStatus': videoAiStatus,
          },
        'status': status,
        if (mediaType != null) 'mediaType': mediaType,
        'mediaUrl': mediaUrl,
        'rejectionReason': rejectionReason,
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
        'restaurant': restaurant?.toJson(),
      };

  Post toEntity() => Post(
        id: id,
        type: PostType.fromApi(type),
        author: author,
        title: title,
        body: body,
        createdAt: createdAt,
        coverSeed: coverSeed ?? id,
        tags: tags,
        imageUrl: imageUrl,
        likeCount: likeCount,
        commentCount: commentCount,
        likedByMe: likedByMe,
        savedByMe: savedByMe,
        isPinned: isPinned,
        videoId: videoId,
        videoDurationSeconds: videoDurationSeconds,
        videoStatus:
            videoAiStatus == null ? null : VideoAiStatus.fromApi(videoAiStatus),
        status: PostStatus.fromApi(status),
        mediaType: PostMediaType.tryParse(mediaType),
        mediaUrl: mediaUrl,
        rejectionReason: rejectionReason,
        updatedAt: updatedAt,
        restaurant: restaurant?.toEntity(),
      );
}

class FeedPageDto {
  const FeedPageDto({required this.items, this.nextCursor});

  factory FeedPageDto.fromJson(Map<String, dynamic> json) => FeedPageDto(
        items: (json['items'] is List<Object?>)
            ? (json['items'] as List<Object?>)
                .whereType<Map<String, dynamic>>()
                .map(PostDto.fromJson)
                .toList()
            : const [],
        nextCursor: json['nextCursor']?.toString(),
      );

  final List<PostDto> items;
  final String? nextCursor;

  FeedPage toEntity() => FeedPage(
        items: items.map((p) => p.toEntity()).toList(),
        nextCursor: nextCursor,
      );
}

/// See the comment wire at the top of this file. Reads `text` too (older
/// builds of the API).
class CommentDto {
  const CommentDto({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    this.postId,
    this.parentId,
    this.updatedAt,
    this.replyCount = 0,
    this.replies = const [],
  });

  factory CommentDto.fromJson(Map<String, dynamic> json) {
    final replies = json['replies'];
    final parsed = replies is List<Object?>
        ? replies
            .whereType<Map<String, dynamic>>()
            .map(CommentDto.fromJson)
            .toList()
        : const <CommentDto>[];
    return CommentDto(
      id: json['id']?.toString() ?? '',
      author: AuthorSummary.fromJsonValue(json['author']),
      text: json['content'] as String? ?? json['text'] as String? ?? '',
      createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
      postId: json['postId']?.toString(),
      parentId: json['parentId']?.toString(),
      updatedAt: readDateTime(json['updatedAt']),
      replyCount: json['replyCount'] == null
          ? parsed.length
          : readInt(json['replyCount']),
      replies: parsed,
    );
  }

  final String id;
  final AuthorSummary author;

  /// `comments.content`.
  final String text;
  final DateTime createdAt;
  final String? postId;
  final String? parentId;
  final DateTime? updatedAt;
  final int replyCount;
  final List<CommentDto> replies;

  Map<String, dynamic> toJson() => {
        'id': id,
        'postId': postId,
        'parentId': parentId,
        'author': author.toJson(),
        'content': text,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
        if (parentId == null) ...{
          'replyCount': replyCount,
          'replies': [for (final r in replies) r.toJson()],
        },
      };

  CommentDto copyWith({
    String? text,
    DateTime? updatedAt,
    int? replyCount,
    List<CommentDto>? replies,
  }) =>
      CommentDto(
        id: id,
        author: author,
        text: text ?? this.text,
        createdAt: createdAt,
        postId: postId,
        parentId: parentId,
        updatedAt: updatedAt ?? this.updatedAt,
        replyCount: replyCount ?? this.replyCount,
        replies: replies ?? this.replies,
      );

  Comment toEntity() => Comment(
        id: id,
        author: author,
        text: text,
        createdAt: createdAt,
        postId: postId,
        parentId: parentId,
        updatedAt: updatedAt,
        replyCount: replyCount,
        replies: [for (final r in replies) r.toEntity()],
      );
}

/// `{ "items": [CommentDto], "nextCursor": "10" | null }`; a bare list (older
/// builds) is one complete page.
class CommentPageDto {
  const CommentPageDto({required this.items, this.nextCursor});

  factory CommentPageDto.fromJson(Object? json) {
    if (json is List<Object?>) {
      return CommentPageDto(
          items: json
              .whereType<Map<String, dynamic>>()
              .map(CommentDto.fromJson)
              .toList());
    }
    final map = readMap(json);
    final items = map['items'];
    return CommentPageDto(
      items: items is List<Object?>
          ? items
              .whereType<Map<String, dynamic>>()
              .map(CommentDto.fromJson)
              .toList()
          : const [],
      nextCursor: map['nextCursor']?.toString(),
    );
  }

  final List<CommentDto> items;
  final String? nextCursor;

  Map<String, dynamic> toJson() => {
        'items': [for (final c in items) c.toJson()],
        'nextCursor': nextCursor,
      };

  CommentPage toEntity() => CommentPage(
      items: [for (final c in items) c.toEntity()], nextCursor: nextCursor);
}

/// GET /users/me/comments
/// `[{ "id", "postId", "postTitle", "parentId", "content", "createdAt", "updatedAt" }]`
class MyCommentDto {
  const MyCommentDto({
    required this.id,
    required this.postId,
    required this.postTitle,
    required this.text,
    required this.createdAt,
    this.parentId,
    this.updatedAt,
  });

  factory MyCommentDto.fromJson(Map<String, dynamic> json) => MyCommentDto(
        id: json['id']?.toString() ?? '',
        postId: json['postId']?.toString() ?? '',
        postTitle: json['postTitle'] as String? ?? '',
        text: json['content'] as String? ?? json['text'] as String? ?? '',
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
        parentId: json['parentId']?.toString(),
        updatedAt: readDateTime(json['updatedAt']),
      );

  final String id;
  final String postId;
  final String postTitle;
  final String text;
  final DateTime createdAt;
  final String? parentId;
  final DateTime? updatedAt;

  MyComment toEntity() => MyComment(
        id: id,
        postId: postId,
        postTitle: postTitle,
        text: text,
        createdAt: createdAt,
        parentId: parentId,
        updatedAt: updatedAt,
      );
}

/// POST /posts. One attachment at most ([mediaType] + [mediaUrl]), links
/// stay in [body]. The server starts the AI recipe pipeline only for
/// Công thức + video.
class CreatePostRequestDto {
  const CreatePostRequestDto({
    required this.type,
    required this.title,
    required this.body,
    this.tags = const [],
    this.mediaType = PostMediaType.text,
    this.mediaUrl,
    this.restaurant,
  });

  final PostType type;
  final String title;
  final String body;
  final List<String> tags;
  final PostMediaType mediaType;
  final String? mediaUrl;

  /// Sent as `restaurantId`; the whole summary is kept so a mock server can
  /// echo it like the real join.
  final TaggedRestaurant? restaurant;

  /// Recipe extraction runs only for Công thức + video.
  bool get wantsAiRecipe =>
      type == PostType.recipe &&
      mediaType == PostMediaType.video &&
      mediaUrl != null;

  Map<String, dynamic> toJson() => {
        'type': type.apiValue,
        'title': title,
        'body': body,
        'tags': tags,
        'mediaType':
            (mediaUrl == null ? PostMediaType.text : mediaType).apiValue,
        'mediaUrl': mediaUrl,
        'restaurantId': restaurant?.id,
      };
}

/// PUT /posts/{id}. The server re-screens the text and returns the new
/// `status` (an edited Rejected post always goes back to Pending). The
/// attachment can't change once posted.
class UpdatePostRequestDto {
  const UpdatePostRequestDto({
    required this.title,
    required this.body,
    this.tags = const [],
    required this.mediaType,
    this.mediaUrl,
    this.restaurant,
  });

  final String title;
  final String body;
  final List<String> tags;
  final PostMediaType mediaType;
  final String? mediaUrl;

  /// `null` removes the tag.
  final TaggedRestaurant? restaurant;

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'tags': tags,
        'mediaType': mediaType.apiValue,
        'mediaUrl': mediaUrl,
        'restaurantId': restaurant?.id,
      };
}
