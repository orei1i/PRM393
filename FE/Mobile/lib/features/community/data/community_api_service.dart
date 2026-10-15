// lib/features/community/data/community_api_service.dart
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/session/session_controller.dart';
import '../domain/entities/post.dart';
import 'mock_community_repository.dart';
import 'models/post_model.dart';

abstract interface class CommunityApiService {
  /// Cursor-paginated feed of `Published` posts, newest first; pinned posts
  /// come first on page 1.
  Future<FeedPageDto> getFeed({PostType? type, String? cursor, int limit = 6});

  /// Non-published posts are 404 for everyone but their author.
  Future<PostDto> getPost(String id);

  Future<void> setLiked(String postId, {required bool liked});

  Future<void> setSaved(String postId, {required bool saved});

  Future<List<CommentDto>> getComments(String postId);

  Future<CommentDto> addComment(String postId, String text);

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

  Future<void> deleteComment(String postId, String commentId);

  /// The member's comments across all posts, newest first.
  Future<List<MyCommentDto>> getMyComments();
}

class RemoteCommunityApiService implements CommunityApiService {
  RemoteCommunityApiService(this._dio);

  final Dio _dio;

  List<PostDto> _posts(Object? data) => data is List<Object?>
      ? data.whereType<Map<String, dynamic>>().map(PostDto.fromJson).toList()
      : const [];

  @override
  Future<FeedPageDto> getFeed(
          {PostType? type, String? cursor, int limit = 6}) =>
      guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(
          ApiEndpoints.feed,
          queryParameters: {
            if (type != null) 'type': type.apiValue,
            if (cursor != null) 'cursor': cursor,
            'limit': limit,
          },
        );
        return FeedPageDto.fromJson(res.data!);
      });

  @override
  Future<PostDto> getPost(String id) => guardApi(() async {
        final res = await _dio.get<Map<String, dynamic>>(ApiEndpoints.post(id));
        return PostDto.fromJson(res.data!);
      });

  @override
  Future<void> setLiked(String postId, {required bool liked}) =>
      guardApi(() async {
        if (liked) {
          await _dio.put<void>(ApiEndpoints.postLike(postId));
        } else {
          await _dio.delete<void>(ApiEndpoints.postLike(postId));
        }
      });

  @override
  Future<void> setSaved(String postId, {required bool saved}) =>
      guardApi(() async {
        if (saved) {
          await _dio.put<void>(ApiEndpoints.postSave(postId));
        } else {
          await _dio.delete<void>(ApiEndpoints.postSave(postId));
        }
      });

  @override
  Future<List<CommentDto>> getComments(String postId) => guardApi(() async {
        final res =
            await _dio.get<List<dynamic>>(ApiEndpoints.postComments(postId));
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(CommentDto.fromJson)
            .toList();
      });

  @override
  Future<CommentDto> addComment(String postId, String text) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          ApiEndpoints.postComments(postId),
          data: {'text': text},
        );
        return CommentDto.fromJson(res.data!);
      });

  @override
  Future<PostDto> createPost(CreatePostRequestDto request) =>
      guardApi(() async {
        final res = await _dio.post<Map<String, dynamic>>(ApiEndpoints.posts,
            data: request.toJson());
        return PostDto.fromJson(res.data!);
      });

  @override
  Future<PostDto> updatePost(String id, UpdatePostRequestDto request) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(ApiEndpoints.post(id),
            data: request.toJson());
        return PostDto.fromJson(res.data!);
      });

  @override
  Future<void> deletePost(String id) => guardApi(() async {
        await _dio.delete<void>(ApiEndpoints.post(id));
      });

  @override
  Future<void> reportPost(String postId,
          {required ReportReason reason, String? note}) =>
      guardApi(() async {
        await _dio.post<void>(
          ApiEndpoints.postReport(postId),
          data: {
            'reason': reason.apiValue,
            if (note != null && note.isNotEmpty) 'note': note
          },
        );
      });

  @override
  Future<List<PostDto>> getMyPosts() => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myPosts);
        return _posts(res.data);
      });

  @override
  Future<List<PostDto>> getSavedPosts() => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.mySavedPosts);
        return _posts(res.data);
      });

  @override
  Future<CommentDto> updateComment(
          String postId, String commentId, String text) =>
      guardApi(() async {
        final res = await _dio.put<Map<String, dynamic>>(
          ApiEndpoints.postComment(postId, commentId),
          data: {'text': text},
        );
        return CommentDto.fromJson(res.data!);
      });

  @override
  Future<void> deleteComment(String postId, String commentId) =>
      guardApi(() async {
        await _dio.delete<void>(ApiEndpoints.postComment(postId, commentId));
      });

  @override
  Future<List<MyCommentDto>> getMyComments() => guardApi(() async {
        final res = await _dio.get<List<dynamic>>(ApiEndpoints.myComments);
        return (res.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(MyCommentDto.fromJson)
            .toList();
      });
}

final communityApiProvider = Provider<CommunityApiService>((ref) {
  if (Env.useMockData) {
    return MockCommunityRepository(
      currentUserName: () =>
          ref.read(sessionControllerProvider).displayName ?? 'Bạn',
      isSignedIn: () => !ref.read(sessionControllerProvider).isGuest,
      currentUserId: () => ref.read(sessionControllerProvider).userId ?? '',
    );
  }
  return RemoteCommunityApiService(ref.watch(dioProvider));
});
