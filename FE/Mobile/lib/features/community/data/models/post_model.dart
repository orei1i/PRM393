// lib/features/community/data/models/post_model.dart
//
// GET /posts?type=recipe&cursor=…&limit=10
// { "items": [ { "id": "p_101", "type": "recipe", "author": { "id": "u_1", "fullName": "…", "isVerifiedChef": false },
//   "title": "…", "body": "…", "tags": ["quick"], "coverSeed": "bun-rieu", "imageUrl": null,
//   "likeCount": 128, "commentCount": 14, "likedByMe": false, "savedByMe": true, "isPinned": false,
//   "createdAt": "2026-10-14T02:10:00Z", "video": { "id": "vid_x", "durationSeconds": 724, "aiStatus": "ready" } } ],
//   "nextCursor": "p_095" }
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
  });

  factory PostDto.fromJson(Map<String, dynamic> json) {
    final video = json['video'];
    final videoMap = video is Map<String, dynamic> ? video : null;
    return PostDto(
      id: json['id']?.toString() ?? '',
      type: json['type'] as String? ?? 'discussion',
      author: AuthorSummary.fromJsonValue(json['author']),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
      coverSeed: json['coverSeed'] as String?,
      tags: readStringList(json['tags']),
      imageUrl: json['imageUrl'] as String?,
      likeCount: readInt(json['likeCount']),
      commentCount: readInt(json['commentCount']),
      likedByMe: json['likedByMe'] == true,
      savedByMe: json['savedByMe'] == true,
      isPinned: json['isPinned'] == true,
      videoId: videoMap?['id']?.toString(),
      videoDurationSeconds:
          videoMap == null ? null : readInt(videoMap['durationSeconds']),
      videoAiStatus: videoMap?['aiStatus'] as String?,
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

class CommentDto {
  const CommentDto(
      {required this.id,
      required this.author,
      required this.text,
      required this.createdAt});

  factory CommentDto.fromJson(Map<String, dynamic> json) => CommentDto(
        id: json['id']?.toString() ?? '',
        author: AuthorSummary.fromJsonValue(json['author']),
        text: json['text'] as String? ?? '',
        createdAt: readDateTime(json['createdAt']) ?? DateTime.now(),
      );

  final String id;
  final AuthorSummary author;
  final String text;
  final DateTime createdAt;

  Comment toEntity() =>
      Comment(id: id, author: author, text: text, createdAt: createdAt);
}

/// POST /posts — `videoUrl` only for `type: video` (server starts the AI pipeline).
class CreatePostRequestDto {
  const CreatePostRequestDto({
    required this.type,
    required this.title,
    required this.body,
    this.tags = const [],
    this.videoUrl,
  });

  final PostType type;
  final String title;
  final String body;
  final List<String> tags;
  final String? videoUrl;

  Map<String, dynamic> toJson() => {
        'type': type.apiValue,
        'title': title,
        'body': body,
        'tags': tags,
        if (videoUrl != null) 'videoUrl': videoUrl,
      };
}
