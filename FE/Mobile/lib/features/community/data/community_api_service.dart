// lib/features/community/data/community_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/backend_modules.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/session_controller.dart';
import '../domain/entities/post.dart';
import 'backend_posts.dart';
import 'mock_community_repository.dart';
import 'models/post_model.dart';

abstract interface class CommunityApiService {
  /// Cursor-paginated feed of `Published` posts, newest first; pinned posts
  /// come first on page 1. [type] filters Công thức / Hỏi đáp, [mediaType]
  /// the attachment ("Có video", Reels).
  Future<FeedPageDto> getFeed({
    PostType? type,
    PostMediaType? mediaType,
    String? cursor,
    int limit = 6,
  });

  /// Non-published posts are 404 for everyone but their author.
  Future<PostDto> getPost(String id);

  Future<void> setLiked(String postId, {required bool liked});

  Future<void> setSaved(String postId, {required bool saved});

  /// Top-level comments, newest first, [limit] per page; each previews its
  /// first 2 replies (`replyCount` says how many there are).
  Future<CommentPageDto> getComments(String postId,
      {String? cursor, int limit = 10});

  /// Replies of a top-level comment, oldest first.
  Future<CommentPageDto> getReplies(String postId, String commentId,
      {String? cursor, int limit = 20});

  /// [parentId] answers a top-level comment (one level deep: a reply to a
  /// reply is attached to the same top-level comment by the caller).
  Future<CommentDto> addComment(String postId, String text, {String? parentId});

  /// The server pre-screens the text: `Published`, or `Pending` when the AI
  /// flags it (hidden from the feed until an admin approves).
  Future<PostDto> createPost(CreatePostRequestDto request);

  /// Author only (403 otherwise). Re-screened like a new post; an edited
  /// `Rejected` post always goes back to `Pending`.
  Future<PostDto> updatePost(String id, UpdatePostRequestDto request);

  /// Author only; removes the post with its comments.
  Future<void> deletePost(String id);

  /// Lands in the admin moderation queue on the web console.
  Future<void> reportPost(String postId,
      {required ReportReason reason, String? note});

  /// Every status, with `rejectionReason` on rejected posts.
  Future<List<PostDto>> getMyPosts();

  Future<List<PostDto>> getSavedPosts();

  Future<CommentDto> updateComment(
      String postId, String commentId, String text);

  /// Author only. A top-level comment takes its replies with it.
  Future<void> deleteComment(String postId, String commentId);

  /// The member's comments across all posts, newest first.
  Future<List<MyCommentDto>> getMyComments();
}

/// The real BE. Its contract differs from [CommunityApiService] in these ways,
/// all absorbed here so the screens stay the same:
/// - Paging is `page` / `pageSize`; a cursor here is simply the next page.
/// - Like is a toggle (POST).
/// - No save, my-posts, my-comments, reply paging or edit routes: saves stay on
///   this device ([SavedPostsStore]), my posts come from the feed, and the UI
///   hides the rest through the `BackendModules` capabilities.
class RemoteCommunityApiService implements CommunityApiService {
  RemoteCommunityApiService(
    this._dio, {
    String? Function()? currentUserId,
    SavedPostsStore? saved,
  })  : _currentUserId = currentUserId ?? _noUser,
        _saved =
            saved ?? SavedPostsStore(currentUserId: currentUserId ?? _noUser);

  static String? _noUser() => null;

  /// How far "Bài của tôi" scans the feed: 5 × 50 = the 250 newest posts.
  static const myPostsPageSize = backendMaxPageSize;
  static const myPostsMaxPages = 5;

  final Dio _dio;
  final String? Function() _currentUserId;
  final SavedPostsStore _saved;

  /// The last [getMyPosts] stopped before the end of the feed.
  bool get myPostsTruncated => _myPostsTruncated;
  bool _myPostsTruncated = false;

  PostDto _post(Map<String, dynamic> json) =>
      PostDto.fromJson(adaptBackendPost(json, _saved));

  List<PostDto> _posts(Object? items) => items is List<Object?>
      ? items.whereType<Map<String, dynamic>>().map(_post).toList()
      : const [];

  /// The BE stamps `updatedAt` on every comment, edited or not (B17), and has
  /// no edit route: without this every comment reads "(đã sửa)".
  Map<String, dynamic> _commentJson(Map<String, dynamic> json) {
    final replies = json['replies'];
    return {
      ...json,
      if (!BackendModules.commentEdit) 'updatedAt': null,
      if (replies is List<Object?>)
        'replies': replies
            .whereType<Map<String, dynamic>>()
            .map(_commentJson)
            .toList(),
    };
  }

  static int _pageOf(String? cursor) => int.tryParse(cursor ?? '') ?? 1;

  static int _pageSize(int limit) => limit.clamp(1, backendMaxPageSize);

  @override
  Future<FeedPageDto> getFeed({
    PostType? type,
    PostMediaType? mediaType,
    String? cursor,
    int limit = 6,
  }) =>
      guardApi(() async {
        final page = _pageOf(cursor);
        final pageSize = _pageSize(limit);
        final res = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.feed,
          queryParameters: {
            if (type != null) 'type': type.apiValue,
            if (mediaType != null) 'mediaType': mediaType.apiValue,
            'page': page,
            'pageSize': pageSize,
          },
        );
        final body = res.data!;
        final items = _posts(body['items']);
        return FeedPageDto(
          items: items,
          nextCursor: nextFeedCursor(body,
              page: page, limit: pageSize, itemCount: items.length),
        );
      });

  @override
  Future<PostDto> getPost(String id) => guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(ApiEndpoints.post(id));
        return _post(res.data!);
      });

  /// The BE toggles, so a request that crossed another one (double tap, a
  /// second device) can land on the wrong state: toggle back once.
  @override
  Future<void> setLiked(String postId, {required bool liked}) =>
      guardApi(() async {
        Future<Object?> toggle() async => (await _dio
                .post<Map<String, dynamic>>(ApiEndpoints.postLike(postId)))
            .data?['liked'];
        final now = await toggle();
        if (now is bool && now != liked) await toggle();
      });

  @override
  Future<void> setSaved(String postId, {required bool saved}) =>
      _saved.setSaved(postId, saved: saved);

  @override
  Future<CommentPageDto> getComments(String postId,
          {String? cursor, int limit = 10}) =>
      guardApi(() async {
        final page = _pageOf(cursor);
        final pageSize = _pageSize(limit);
        final res = await _dio.get<Object?>(
          ApiEndpoints.postComments(postId),
          queryParameters: {'page': page, 'pageSize': pageSize},
        );
        // A plain array, with no total: a full page may have a next one.
        final data = res.data;
        final raw = data is Map<String, dynamic> ? data['items'] : data;
        final items = raw is List<Object?>
            ? raw
                .whereType<Map<String, dynamic>>()
                .map((c) => CommentDto.fromJson(_commentJson(c)))
                .toList()
            : const <CommentDto>[];
        return CommentPageDto(
          items: items,
          nextCursor: items.length >= pageSize ? '${page + 1}' : null,
        );
      });

  /// No route on the BE yet: replies past the 2 previewed ones are unreachable,
  /// and the thread says so instead of offering "Xem thêm".
  @override
  Future<CommentPageDto> getReplies(String postId, String commentId,
      {String? cursor, int limit = 20}) {
    if (!BackendModules.commentReplyPaging) {
      return Future.value(const CommentPageDto(items: []));
    }
    return guardApi(() async {
      final res = await _dio.get<Object?>(
        ApiEndpoints.commentReplies(postId, commentId),
        queryParameters: {if (cursor != null) 'cursor': cursor, 'limit': limit},
      );
      return CommentPageDto.fromJson(res.data);
    });
  }

  @override
  Future<CommentDto> addComment(String postId, String text,
          {String? parentId}) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.postComments(postId),
          data: {'content': text, if (parentId != null) 'parentId': parentId},
        );
        return CommentDto.fromJson(_commentJson(res.data!));
      });

  @override
  Future<PostDto> createPost(CreatePostRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(ApiEndpoints.posts,
            data: request.toJson());
        return _post(res.data!);
      });

  @override
  Future<PostDto> updatePost(String id, UpdatePostRequestDto request) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(ApiEndpoints.post(id),
            data: request.toJson());
        return _post(res.data!);
      });

  @override
  Future<void> deletePost(String id) => guardApi(() async {
        await _dio.delete<void>(ApiEndpoints.post(id));
        await _saved.setSaved(id, saved: false);
      });

  /// The BE keeps only `reason` (at most 500 characters), so a note goes in it.
  @override
  Future<void> reportPost(String postId,
          {required ReportReason reason, String? note}) =>
      guardApi(() async {
        final text = note == null || note.trim().isEmpty
            ? reason.apiValue
            : '${reason.apiValue}: ${note.trim()}';
        await _dio.post<void>(
          ApiEndpoints.postReport(postId),
          data: {
            'reason': text.length > _maxReportReason
                ? text.substring(0, _maxReportReason)
                : text,
          },
        );
      });

  static const _maxReportReason = 500;

  /// The member's posts among the newest [myPostsMaxPages] pages of the feed
  /// (the BE has no `/users/me/posts`), so published ones only.
  @override
  Future<List<PostDto>> getMyPosts() => guardApi(() async {
        final me = _currentUserId();
        _myPostsTruncated = false;
        if (me == null) return const [];
        final mine = <PostDto>[];
        for (var page = 1; page <= myPostsMaxPages; page++) {
          final res = await _dio.get<Map<String, dynamic>>(
            ApiEndpoints.feed,
            queryParameters: {'page': page, 'pageSize': myPostsPageSize},
          );
          final body = res.data!;
          final posts = _posts(body['items']);
          mine.addAll(posts.where((p) => p.author.id == me));
          final next = nextFeedCursor(body,
              page: page, limit: myPostsPageSize, itemCount: posts.length);
          if (next == null) return mine;
        }
        _myPostsTruncated = true;
        return mine;
      });

  /// Newest saved first. A post that is gone (deleted, or hidden by reports)
  /// is skipped, not forgotten: a hidden one may come back.
  @override
  Future<List<PostDto>> getSavedPosts() async {
    final posts = await Future.wait(_saved.ids.map(_savedPost));
    return posts.whereType<PostDto>().toList();
  }

  Future<PostDto?> _savedPost(String id) async {
    try {
      return await getPost(id);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<CommentDto> updateComment(
          String postId, String commentId, String text) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(
          ApiEndpoints.postComment(postId, commentId),
          data: {'content': text},
        );
        return CommentDto.fromJson(res.data!);
      });

  @override
  Future<void> deleteComment(String postId, String commentId) =>
      guardApi(() async {
        await _dio.delete<void>(ApiEndpoints.commentDelete(commentId));
      });

  /// No route on the BE yet; the "Bình luận" tab says so instead of asking.
  @override
  Future<List<MyCommentDto>> getMyComments() {
    if (!BackendModules.myComments) return Future.value(const []);
    return guardApi(() async {
      final res = await _dio.get<List<dynamic>>(ApiEndpoints.myComments);
      return (res.data ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MyCommentDto.fromJson)
          .toList();
    });
  }
}

final communityApiProvider = Provider<CommunityApiService>((ref) {
  if (BackendModules.isMock(BackendModule.community)) {
    return MockCommunityRepository(
      currentUserName: () =>
          ref.read(sessionControllerProvider).displayName ?? 'Bạn',
      isSignedIn: () => !ref.read(sessionControllerProvider).isGuest,
      currentUserId: () => ref.read(sessionControllerProvider).userId ?? '',
    );
  }
  return RemoteCommunityApiService(
    ref.watch(dioProvider),
    currentUserId: () => ref.read(sessionControllerProvider).userId,
    saved: ref.watch(savedPostsStoreProvider),
  );
});
