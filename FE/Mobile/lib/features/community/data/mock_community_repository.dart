// lib/features/community/data/mock_community_repository.dart
import 'dart:math' as math;

import '../../../core/models/author_summary.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/mock_delay.dart';
import '../../video/data/mock/mock_video_store.dart';
import '../domain/entities/post.dart';
import 'community_api_service.dart';
import 'mock/community_mock_data.dart';
import 'models/post_model.dart';

/// In-memory community backend. State is static so it survives provider
/// rebuilds (sign-in/out) for the whole app session.
class MockCommunityRepository implements CommunityApiService {
  MockCommunityRepository({required this.currentUserName});

  final String Function() currentUserName;

  static const _meId = 'u_me';
  static final _db = _MockCommunityDb();

  AuthorSummary get _me => AuthorSummary(id: _meId, name: currentUserName());

  PostDto _withLiveVideoStatus(PostDto post) {
    final videoId = post.videoId;
    if (videoId == null) return post;
    final video = MockVideoStore.instance.get(videoId);
    if (video == null || video.aiStatus == post.videoAiStatus) return post;
    final json = post.toJson();
    (json['video'] as Map<String, dynamic>)['aiStatus'] = video.aiStatus;
    return PostDto.fromJson(json);
  }

  PostDto _decorate(PostDto post) {
    final json = _withLiveVideoStatus(post).toJson()
      ..['likedByMe'] = _db.liked.contains(post.id)
      ..['savedByMe'] = _db.saved.contains(post.id)
      ..['commentCount'] = post.commentCount +
          (_db.comments[post.id]?.length ?? 0) -
          _seedCount(post.id);
    return PostDto.fromJson(json);
  }

  int _seedCount(String postId) => seedComments[postId]?.length ?? 0;

  bool _visibleInFeed(PostDto p) =>
      p.author.id == _meId ||
      p.videoAiStatus == null ||
      p.videoAiStatus == 'ready';

  @override
  Future<FeedPageDto> getFeed(
      {PostType? type, String? cursor, int limit = 6}) async {
    await mockDelay(cursor == null ? 800 : 600);
    final all = _db.posts
        .where(_visibleInFeed)
        .where((p) => type == null || p.type == type.apiValue)
        .toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    final start = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    final end = math.min(start + limit, all.length);
    return FeedPageDto(
      items: all.sublist(start, end).map(_decorate).toList(),
      nextCursor: end < all.length ? '$end' : null,
    );
  }

  @override
  Future<PostDto> getPost(String id) async {
    await mockDelay(300);
    return _decorate(_db.find(id));
  }

  @override
  Future<void> setLiked(String postId, {required bool liked}) async {
    await mockDelay(250);
    _db.find(postId);
    if (liked) {
      _db.liked.add(postId);
    } else {
      _db.liked.remove(postId);
    }
  }

  @override
  Future<void> setSaved(String postId, {required bool saved}) async {
    await mockDelay(250);
    _db.find(postId);
    if (saved) {
      _db.saved.add(postId);
    } else {
      _db.saved.remove(postId);
    }
  }

  @override
  Future<List<CommentDto>> getComments(String postId) async {
    await mockDelay(500);
    return List.of(_db.comments[postId] ?? const <CommentDto>[]);
  }

  @override
  Future<CommentDto> addComment(String postId, String text) async {
    await mockDelay(450);
    if (text.toLowerCase().contains('#fail')) {
      throw const ApiException(
          message: 'Chưa gửi được bình luận. Thử lại nhé.', statusCode: 503);
    }
    final comment = CommentDto(
      id: 'c_${DateTime.now().microsecondsSinceEpoch}',
      author: _me,
      text: text,
      createdAt: DateTime.now(),
    );
    (_db.comments[postId] ??= []).add(comment);
    return comment;
  }

  @override
  Future<PostDto> createPost(CreatePostRequestDto request) async {
    await mockDelay(900);
    final id = 'p_${DateTime.now().millisecondsSinceEpoch}';
    String? videoId;
    if (request.type == PostType.video && request.videoUrl != null) {
      videoId = MockVideoStore.instance.createFromLink(
          title: request.title, author: _me, url: request.videoUrl!);
    }
    final post = PostDto(
      id: id,
      type: request.type.apiValue,
      author: _me,
      title: request.title,
      body: request.body,
      createdAt: DateTime.now(),
      coverSeed: id,
      tags: request.tags,
      videoId: videoId,
      videoDurationSeconds: videoId == null ? null : 300,
      videoAiStatus: videoId == null ? null : 'queued',
    );
    _db.posts.insert(0, post);
    return _decorate(post);
  }

  @override
  Future<void> reportPost(String postId,
      {required ReportReason reason, String? note}) async {
    await mockDelay(500);
    _db.find(postId);
  }

  @override
  Future<List<PostDto>> getMyPosts() async {
    await mockDelay(500);
    return _db.posts.where((p) => p.author.id == _meId).map(_decorate).toList();
  }

  @override
  Future<List<PostDto>> getSavedPosts() async {
    await mockDelay(500);
    return _db.posts
        .where((p) => _db.saved.contains(p.id))
        .map(_decorate)
        .toList();
  }
}

class _MockCommunityDb {
  _MockCommunityDb() {
    posts.addAll(buildSeedPosts().map(PostDto.fromJson));
    saved.addAll(['p_video_meal_prep', 'p_dam_thuc_vat']);
    seedComments.forEach((postId, items) {
      var i = 0;
      comments[postId] = [
        for (final c in items)
          CommentDto(
            id: 'c_${postId}_${i++}',
            author: AuthorSummary.fromJson(
                Map<String, dynamic>.from(c['author']! as Map)),
            text: c['text']! as String,
            createdAt: DateTime.now()
                .subtract(Duration(minutes: c['minutesAgo']! as int)),
          ),
      ];
    });
  }

  final List<PostDto> posts = [];
  final Set<String> liked = {};
  final Set<String> saved = {};
  final Map<String, List<CommentDto>> comments = {};

  PostDto find(String id) => posts.firstWhere(
        (p) => p.id == id,
        orElse: () => throw const ApiException(
            message: 'Bài viết đã bị xoá hoặc ẩn.', statusCode: 404),
      );
}
