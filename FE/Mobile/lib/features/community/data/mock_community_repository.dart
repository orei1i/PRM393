// lib/features/community/data/mock_community_repository.dart
import 'dart:math' as math;

import '../../../core/models/author_summary.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/mock_delay.dart';
import '../../../core/utils/text_search.dart';
import '../../video/data/mock/mock_video_store.dart';
import '../domain/entities/post.dart';
import 'community_api_service.dart';
import 'media_api_service.dart';
import 'mock/community_mock_data.dart';
import 'models/post_model.dart';

/// In-memory community backend. State is static so it survives provider
/// rebuilds (sign-in/out, account switches) for the whole app session.
/// Likes, saves and "my posts" belong to the signed-in member: guests see
/// the public view, like the real API without a bearer token.
///
/// Posts follow the "publish unless AI flags" rule: [preScreenFlags] holds a
/// new or edited post as `Pending` (hidden from the feed, shown to its
/// author); an edited `Rejected` post always goes back to `Pending`.
class MockCommunityRepository implements CommunityApiService {
  MockCommunityRepository({
    required this.currentUserName,
    required this.isSignedIn,
    String Function()? currentUserId,
  }) : currentUserId = currentUserId ?? _demoMemberId;

  final String Function() currentUserName;
  final bool Function() isSignedIn;

  /// Signed-in user's id; the demo member Minh Anh unless the session says
  /// otherwise.
  final String Function() currentUserId;

  static String _demoMemberId() => 'u_me';
  static final _db = _MockCommunityDb();

  /// What the server's synchronous AI pre-screen flags (matched on folded
  /// text, so "chua khoi" counts too).
  static const flagTriggers = [
    '#flag',
    'chữa khỏi',
    'giảm cân thần tốc',
    'inbox',
    'zalo',
    'cam kết hoàn tiền',
  ];

  static bool preScreenFlags(String title, String body) {
    final text = foldVietnamese('$title\n$body');
    return flagTriggers.any((w) => text.contains(foldVietnamese(w)));
  }

  static bool _fails(String text) => text.toLowerCase().contains('#fail');

  String? get _meId => isSignedIn() ? currentUserId() : null;

  bool _isMine(PostDto p) => _meId != null && p.author.id == _meId;

  AuthorSummary get _me => AuthorSummary(
        id: currentUserId(),
        name: currentUserName(),
        isVerifiedChef: _db.isVerifiedChef(currentUserId()),
      );

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
    final me = _meId;
    final json = _withLiveVideoStatus(post).toJson()
      ..['likedByMe'] = me != null && _db.likedBy(me).contains(post.id)
      ..['savedByMe'] = me != null && _db.savedBy(me).contains(post.id)
      // Seed counts don't include likes given in this session.
      ..['likeCount'] = post.likeCount + _db.sessionLikes(post.id)
      // The thread is the source of truth, so the card, the detail screen
      // and the comments sheet always agree.
      ..['commentCount'] = _db.comments[post.id]?.length ?? 0;
    return PostDto.fromJson(json);
  }

  void _requireMember() {
    if (!isSignedIn()) {
      throw const ApiException(
          message: 'Vui lòng đăng nhập để tiếp tục.', statusCode: 401);
    }
  }

  static const _notFound =
      ApiException(message: 'Bài viết đã bị xoá hoặc ẩn.', statusCode: 404);

  static const _notYours = ApiException(
      message: 'Bạn chỉ sửa được nội dung của mình.', statusCode: 403);

  bool _isPublished(PostDto p) => p.status == PostStatus.published.apiValue;

  /// A post the caller may see: published, or their own.
  PostDto _findVisible(String id) {
    final post = _db.find(id);
    if (!_isPublished(post) && !_isMine(post)) throw _notFound;
    return post;
  }

  PostDto _findOwn(String id) {
    final post = _db.find(id);
    if (!_isMine(post)) throw _notYours;
    return post;
  }

  /// Published only; the author also sees their videos while AI processes
  /// them.
  bool _visibleInFeed(PostDto p) =>
      _isPublished(p) &&
      (_isMine(p) || p.videoAiStatus == null || p.videoAiStatus == 'ready');

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
    return _decorate(_findVisible(id));
  }

  @override
  Future<void> setLiked(String postId, {required bool liked}) async {
    await mockDelay(250);
    _requireMember();
    _findVisible(postId);
    final mine = _db.likedBy(_meId!);
    if (liked) {
      mine.add(postId);
    } else {
      mine.remove(postId);
    }
  }

  @override
  Future<void> setSaved(String postId, {required bool saved}) async {
    await mockDelay(250);
    _requireMember();
    _findVisible(postId);
    final mine = _db.savedBy(_meId!);
    if (saved) {
      mine.add(postId);
    } else {
      mine.remove(postId);
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
    _requireMember();
    if (_fails(text)) {
      throw const ApiException(
          message: 'Chưa gửi được bình luận. Thử lại nhé.', statusCode: 503);
    }
    _findVisible(postId);
    final comment = CommentDto(
      id: 'c_${DateTime.now().microsecondsSinceEpoch}',
      postId: postId,
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
    _requireMember();
    if (_fails(request.title) || _fails(request.body)) {
      throw const ApiException(
          message: 'Chưa đăng được bài. Thử lại nhé.', statusCode: 503);
    }
    final id = 'p_${DateTime.now().millisecondsSinceEpoch}';
    final url = request.resolvedMediaUrl;
    String? videoId;
    int? duration;
    if (request.type == PostType.video && url != null) {
      duration = MockMediaRepository.durationOf(url) ?? 300;
      videoId = MockVideoStore.instance.createFromLink(
          title: request.title,
          author: _me,
          url: url,
          durationSeconds: duration);
    }
    final flagged = preScreenFlags(request.title, request.body);
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
      videoDurationSeconds: duration,
      videoAiStatus: videoId == null ? null : 'queued',
      status: (flagged ? PostStatus.pending : PostStatus.published).apiValue,
      mediaType: request.resolvedMediaType.apiValue,
      mediaUrl: url,
    );
    _db.posts.insert(0, post);
    return _decorate(post);
  }

  @override
  Future<PostDto> updatePost(String id, UpdatePostRequestDto request) async {
    await mockDelay(800);
    _requireMember();
    final post = _findOwn(id);
    if (_fails(request.title) || _fails(request.body)) {
      throw const ApiException(
          message: 'Chưa lưu được bài viết. Thử lại nhé.', statusCode: 503);
    }
    final before = PostStatus.fromApi(post.status);
    final flagged = preScreenFlags(request.title, request.body);
    final after = switch (before) {
      // Re-review: the moderation decision is upserted.
      PostStatus.rejected || PostStatus.pending => PostStatus.pending,
      PostStatus.published => flagged ? PostStatus.pending : before,
    };
    final updated = PostDto.fromJson(post.toJson()
      ..['title'] = request.title
      ..['body'] = request.body
      ..['tags'] = request.tags
      ..['mediaType'] = request.mediaType.apiValue
      ..['mediaUrl'] = request.mediaUrl ?? post.mediaUrl
      ..['status'] = after.apiValue
      ..['rejectionReason'] = null
      ..['updatedAt'] = DateTime.now().toUtc().toIso8601String());
    _db.replace(updated);
    return _decorate(updated);
  }

  @override
  Future<void> deletePost(String id) async {
    await mockDelay(600);
    _requireMember();
    _findOwn(id);
    _db.remove(id);
  }

  @override
  Future<void> reportPost(String postId,
      {required ReportReason reason, String? note}) async {
    await mockDelay(500);
    _findVisible(postId);
  }

  @override
  Future<List<PostDto>> getMyPosts() async {
    await mockDelay(500);
    if (!isSignedIn()) return const [];
    return (_db.posts.where(_isMine).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
        .map(_decorate)
        .toList();
  }

  @override
  Future<List<PostDto>> getSavedPosts() async {
    await mockDelay(500);
    final me = _meId;
    if (me == null) return const [];
    final saved = _db.savedBy(me);
    return _db.posts
        .where((p) => saved.contains(p.id))
        .where((p) => _isPublished(p) || _isMine(p))
        .map(_decorate)
        .toList();
  }

  (List<CommentDto>, int) _findComment(String postId, String commentId) {
    final thread = _db.comments[postId] ?? const <CommentDto>[];
    final index = thread.indexWhere((c) => c.id == commentId);
    if (index < 0) {
      throw const ApiException(
          message: 'Bình luận đã bị xoá.', statusCode: 404);
    }
    if (thread[index].author.id != _meId) throw _notYours;
    return (thread, index);
  }

  @override
  Future<CommentDto> updateComment(
      String postId, String commentId, String text) async {
    await mockDelay(450);
    _requireMember();
    final (thread, index) = _findComment(postId, commentId);
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const ApiException(
          message: 'Bình luận không được để trống.', statusCode: 400);
    }
    if (_fails(trimmed)) {
      throw const ApiException(
          message: 'Chưa lưu được bình luận. Thử lại nhé.', statusCode: 503);
    }
    return thread[index] =
        thread[index].copyWith(text: trimmed, updatedAt: DateTime.now());
  }

  @override
  Future<void> deleteComment(String postId, String commentId) async {
    await mockDelay(400);
    _requireMember();
    final (thread, index) = _findComment(postId, commentId);
    thread.removeAt(index);
  }

  @override
  Future<List<MyCommentDto>> getMyComments() async {
    await mockDelay(500);
    final me = _meId;
    if (me == null) return const [];
    final titles = {for (final p in _db.posts) p.id: p.title};
    final mine = [
      for (final MapEntry(key: postId, value: thread) in _db.comments.entries)
        if (titles[postId] case final title?)
          for (final c in thread)
            if (c.author.id == me)
              MyCommentDto(
                id: c.id,
                postId: postId,
                postTitle: title,
                text: c.text,
                createdAt: c.createdAt,
                updatedAt: c.updatedAt,
              ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return mine;
  }
}

class _MockCommunityDb {
  _MockCommunityDb() {
    posts.addAll(buildSeedPosts().map(PostDto.fromJson));
    savedBy('u_me').addAll(['p_video_meal_prep', 'p_dam_thuc_vat']);
    final now = DateTime.now();
    for (final post in posts) {
      comments[post.id] = _seedThread(post, now);
    }
  }

  /// Hand-written comments first, then generated replies up to the seed
  /// `commentCount`, spread between the last of those and now.
  static List<CommentDto> _seedThread(PostDto post, DateTime now) {
    var i = 0;
    AuthorSummary author(Object? json) =>
        AuthorSummary.fromJson(Map<String, dynamic>.from(json! as Map));

    final written = [
      for (final c in seedComments[post.id] ?? const <Map<String, Object>>[])
        CommentDto(
          id: 'c_${post.id}_${i++}',
          postId: post.id,
          author: author(c['author']),
          text: c['text']! as String,
          createdAt: now.subtract(Duration(minutes: c['minutesAgo']! as int)),
        ),
    ];
    final fillers = buildFillerComments(
      postId: post.id,
      postType: post.type,
      postAuthorId: post.author.id,
      count: post.commentCount - written.length,
    );
    final from = written.isEmpty ? post.createdAt : written.last.createdAt;
    final span = now.subtract(const Duration(minutes: 1)).difference(from);
    return [
      ...written,
      for (var k = 0; k < fillers.length; k++)
        CommentDto(
          id: 'c_${post.id}_${i++}',
          postId: post.id,
          author: author(fillers[k]['author']),
          text: fillers[k]['text']! as String,
          createdAt: from.add(span * ((k + 1) / (fillers.length + 1))),
        ),
    ];
  }

  final List<PostDto> posts = [];
  final Map<String, List<CommentDto>> comments = {};

  /// Per user: likes and saves follow the account, not the device.
  final Map<String, Set<String>> _liked = {};
  final Map<String, Set<String>> _saved = {};

  Set<String> likedBy(String userId) => _liked[userId] ??= {};

  Set<String> savedBy(String userId) => _saved[userId] ??= {};

  int sessionLikes(String postId) =>
      _liked.values.where((s) => s.contains(postId)).length;

  bool isVerifiedChef(String userId) =>
      posts.map((p) => p.author).any((a) => a.id == userId && a.isVerifiedChef);

  PostDto find(String id) => posts.firstWhere(
        (p) => p.id == id,
        orElse: () => throw MockCommunityRepository._notFound,
      );

  void replace(PostDto post) {
    final i = posts.indexWhere((p) => p.id == post.id);
    if (i >= 0) posts[i] = post;
  }

  void remove(String postId) {
    posts.removeWhere((p) => p.id == postId);
    comments.remove(postId);
    for (final s in [..._liked.values, ..._saved.values]) {
      s.remove(postId);
    }
  }
}
