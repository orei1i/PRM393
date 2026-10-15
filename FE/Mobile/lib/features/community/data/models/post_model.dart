// lib/features/community/data/models/post_model.dart
//
// GET /posts?type=recipe&cursor=…&limit=10
// { "items": [ { "id": "p_101", "type": "recipe", "author": { "id": "u_1", "fullName": "…", "isVerifiedChef": false },
//   "title": "…", "body": "…", "tags": ["quick"], "coverSeed": "bun-rieu", "imageUrl": null,
//   "likeCount": 128, "commentCount": 14, "likedByMe": false, "savedByMe": true, "isPinned": false,
//   "createdAt": "2026-10-14T02:10:00Z", "video": { "id": "vid_x", "durationSeconds": 724, "aiStatus": "ready" },
//   "status": "Published", "mediaType": "Text", "mediaUrl": null, "rejectionReason": null, "updatedAt": null } ],
//   "nextCursor": "p_095" }
//
// `status` / `mediaType` follow posts.status / posts.media_type. Missing
// `status` → Published (legacy); missing `mediaType` → derived from `type`.
import '../../../../core/models/author_summary.dart';
import '../../../../core/utils/json_helpers.dart';
import '../../../video/domain/entities/video_recipe.dart';
import '../../domain/entities/post.dart';

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
  });

  factory PostDto.fromJson(Map<String, dynamic> json) {
    final video = json['video'];
    final videoMap = video is Map<String, dynamic> ? video : null;
    final type = json['type'] as String? ?? 'discussion';
    final imageUrl = json['imageUrl'] as String?;
    return PostDto(
      id: json['id']?.toString() ?? '',
      type: type,
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
      videoId: videoMap?['id']?.toString(),
      videoDurationSeconds:
          videoMap == null ? null : readInt(videoMap['durationSeconds']),
      videoAiStatus: videoMap?['aiStatus'] as String?,
      status: PostStatus.fromApi(json['status']).apiValue,
      mediaType: (PostMediaType.tryParse(json['mediaType']) ??
              PostMediaType.derive(type: type, imageUrl: imageUrl))
          .apiValue,
      mediaUrl: json['mediaUrl'] as String?,
      rejectionReason: json['rejectionReason'] as String?,
      updatedAt: readDateTime(json['updatedAt']),
    );
  }

  final String id;
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
        nextCursor: json['nextCursor'] as String?,
      );

  final List<PostDto> items;
  final String? nextCursor;

  FeedPage toEntity() => FeedPage(
        items: items.map((p) => p.toEntity()).toList(),
        nextCursor: nextCursor,
      );
}

/// `{ "id", "postId", "author", "text", "createdAt", "updatedAt" }`;
/// `updatedAt` is set once the author edits it.
class CommentDto {
  const CommentDto({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
    this.postId,
    this.updatedAt,
  });

  factory CommentDto.fromJson(Map<String, dynamic> json) => CommentDto(
        id: json['id']?.toString() ?? '',
        author: AuthorSummary.fromJsonValue(json['author']),
        text: json['text'] as String? ?? json['content'] as String? ?? '',
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
        postId: json['postId']?.toString(),
        updatedAt: readDateTime(json['updatedAt']),
      );

  final String id;
  final AuthorSummary author;
  final String text;
  final DateTime createdAt;
  final String? postId;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'postId': postId,
        'author': author.toJson(),
        'text': text,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt?.toUtc().toIso8601String(),
      };

  CommentDto copyWith({String? text, DateTime? updatedAt}) => CommentDto(
        id: id,
        author: author,
        text: text ?? this.text,
        createdAt: createdAt,
        postId: postId,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Comment toEntity() => Comment(
        id: id,
        author: author,
        text: text,
        createdAt: createdAt,
        postId: postId,
        updatedAt: updatedAt,
      );
}

/// GET /users/me/comments
/// `[{ "id", "postId", "postTitle", "text", "createdAt", "updatedAt" }]`
class MyCommentDto {
  const MyCommentDto({
    required this.id,
    required this.postId,
    required this.postTitle,
    required this.text,
    required this.createdAt,
    this.updatedAt,
  });

  factory MyCommentDto.fromJson(Map<String, dynamic> json) => MyCommentDto(
        id: json['id']?.toString() ?? '',
        postId: json['postId']?.toString() ?? '',
        postTitle: json['postTitle'] as String? ?? '',
        text: json['text'] as String? ?? json['content'] as String? ?? '',
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
        updatedAt: readDateTime(json['updatedAt']),
      );

  final String id;
  final String postId;
  final String postTitle;
  final String text;
  final DateTime createdAt;
  final DateTime? updatedAt;

  MyComment toEntity() => MyComment(
        id: id,
        postId: postId,
        postTitle: postTitle,
        text: text,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

/// POST /posts. A video post sends its link or uploaded file URL as
/// `mediaUrl` (plus the legacy `videoUrl` key with the same value); the
/// server starts the AI pipeline either way.
class CreatePostRequestDto {
  const CreatePostRequestDto({
    required this.type,
    required this.title,
    required this.body,
    this.tags = const [],
    this.videoUrl,
    this.mediaType,
    this.mediaUrl,
  });

  final PostType type;
  final String title;
  final String body;
  final List<String> tags;

  /// Legacy name of [mediaUrl] for video posts.
  final String? videoUrl;
  final PostMediaType? mediaType;
  final String? mediaUrl;

  PostMediaType get resolvedMediaType =>
      mediaType ??
      (type == PostType.video ? PostMediaType.video : PostMediaType.text);

  String? get resolvedMediaUrl => mediaUrl ?? videoUrl;

  Map<String, dynamic> toJson() {
    final url = resolvedMediaUrl;
    return {
      'type': type.apiValue,
      'title': title,
      'body': body,
      'tags': tags,
      'mediaType': resolvedMediaType.apiValue,
      if (url != null) 'mediaUrl': url,
      if (type == PostType.video && url != null) 'videoUrl': url,
    };
  }
}

/// PUT /posts/{id}. The server re-screens the text and returns the new
/// `status` (an edited Rejected post always goes back to Pending).
class UpdatePostRequestDto {
  const UpdatePostRequestDto({
    required this.title,
    required this.body,
    this.tags = const [],
    required this.mediaType,
    this.mediaUrl,
  });

  final String title;
  final String body;
  final List<String> tags;
  final PostMediaType mediaType;
  final String? mediaUrl;

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'tags': tags,
        'mediaType': mediaType.apiValue,
        'mediaUrl': mediaUrl,
      };
}
