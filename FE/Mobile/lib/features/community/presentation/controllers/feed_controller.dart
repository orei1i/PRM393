// lib/features/community/presentation/controllers/feed_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../data/community_api_service.dart';
import '../../../video/domain/entities/video_recipe.dart';
import '../../domain/entities/post.dart';

/// The feed's filter chips: Tất cả · Công thức · Hỏi đáp · Có video.
enum FeedFilter {
  all('Tất cả'),
  recipe('Công thức', type: PostType.recipe),
  discussion('Hỏi đáp', type: PostType.discussion),
  video('Có video', mediaType: PostMediaType.video);

  const FeedFilter(this.label, {this.type, this.mediaType});
  final String label;

  /// `GET /posts?type=`.
  final PostType? type;

  /// `GET /posts?mediaType=`.
  final PostMediaType? mediaType;

  /// The Reels strip shows with "Tất cả" and "Có video" only.
  bool get showsReels => this == all || this == video;

  bool matches(Post post) =>
      (type == null || post.type == type) &&
      (mediaType == null || post.mediaType == mediaType);
}

class FeedState {
  const FeedState({
    required this.posts,
    this.filter = FeedFilter.all,
    this.nextCursor,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<Post> posts;
  final FeedFilter filter;
  final String? nextCursor;
  final bool loadingMore;
  final Object? loadMoreError;

  bool get hasMore => nextCursor != null;

  Post? byId(String id) {
    for (final p in posts) {
      if (p.id == id) return p;
    }
    return null;
  }

  FeedState copyWith({
    List<Post>? posts,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingMore,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return FeedState(
      posts: posts ?? this.posts,
      filter: filter,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError:
          clearLoadMoreError ? null : (loadMoreError ?? this.loadMoreError),
    );
  }
}

final feedControllerProvider =
    AsyncNotifierProvider<FeedController, FeedState>(FeedController.new);

/// Bumped after the member posts, edits, deletes, likes, saves or comments.
/// Lists built from the same data elsewhere ("Bài viết của tôi", "Đã lưu",
/// "Bình luận", the stats on "Tôi", Reels) watch it and refetch instead of
/// keeping numbers from before the change.
final communityRevisionProvider =
    NotifierProvider<CommunityRevision, int>(CommunityRevision.new);

class CommunityRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

class FeedController extends AsyncNotifier<FeedState> {
  CommunityApiService get _api => ref.read(communityApiProvider);
  FeedFilter _filter = FeedFilter.all;

  @override
  Future<FeedState> build() async {
    // Re-fetch on sign-in/out: likedByMe / savedByMe are per user.
    ref.watch(sessionControllerProvider.select((s) => s.accessToken));
    return _fetchFirstPage(ref.watch(communityApiProvider));
  }

  Future<FeedState> _fetchFirstPage(CommunityApiService api) async {
    final page =
        (await api.getFeed(type: _filter.type, mediaType: _filter.mediaType))
            .toEntity();
    return FeedState(
        posts: page.items, filter: _filter, nextCursor: page.nextCursor);
  }

  FeedState? get _current => state.hasValue ? state.requireValue : null;

  Future<void> setFilter(FeedFilter filter) async {
    if (filter == _filter && state.hasValue) return;
    _filter = filter;
    state = const AsyncLoading<FeedState>();
    state = await AsyncValue.guard(() => _fetchFirstPage(_api));
  }

  /// Pull-to-refresh. Keeps the current list on failure and rethrows so the
  /// screen can show a snackbar.
  Future<void> refresh() async {
    final fresh = await _fetchFirstPage(_api);
    state = AsyncData(fresh);
  }

  Future<void> loadMore() async {
    final current = _current;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(
        current.copyWith(loadingMore: true, clearLoadMoreError: true));
    try {
      final page = (await _api.getFeed(
        type: current.filter.type,
        mediaType: current.filter.mediaType,
        cursor: current.nextCursor,
      ))
          .toEntity();
      final latest = _current ?? current;
      final known = latest.posts.map((p) => p.id).toSet();
      state = AsyncData(latest.copyWith(
        posts: [
          ...latest.posts,
          ...page.items.where((p) => !known.contains(p.id))
        ],
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        loadingMore: false,
      ));
    } catch (e) {
      final latest = _current ?? current;
      state = AsyncData(latest.copyWith(loadingMore: false, loadMoreError: e));
    }
  }

  // ------------------------------------------------------------ mutations --

  void _changed() => ref.read(communityRevisionProvider.notifier).bump();

  void _replace(Post post) {
    final current = _current;
    if (current == null || current.byId(post.id) == null) return;
    state = AsyncData(current.copyWith(
      posts: [for (final p in current.posts) p.id == post.id ? post : p],
    ));
  }

  /// Optimistic like; rolls back and rethrows on failure.
  Future<void> setLiked(Post post, {required bool liked}) async {
    if (post.likedByMe == liked) return;
    _replace(post.toggledLike());
    try {
      await _api.setLiked(post.id, liked: liked);
      _changed();
    } catch (_) {
      _replace(post);
      rethrow;
    }
  }

  Future<void> setSaved(Post post, {required bool saved}) async {
    if (post.savedByMe == saved) return;
    _replace(post.toggledSave());
    try {
      await _api.setSaved(post.id, saved: saved);
      _changed();
    } catch (_) {
      _replace(post);
      rethrow;
    }
  }

  /// After comments were added (+1) or deleted (−1 − its replies) anywhere:
  /// moves the feed copy's count by [delta].
  void commentsChanged(String postId, int delta) {
    _changed();
    final post = _current?.byId(postId);
    if (post != null && delta != 0) {
      _replace(post.copyWith(
          commentCount: (post.commentCount + delta).clamp(0, 1 << 30)));
    }
  }

  /// Sets the feed copy's count to what the server says (after a delete
  /// whose reply count wasn't known).
  void commentCountIs(String postId, int count) {
    _changed();
    final post = _current?.byId(postId);
    if (post != null && post.commentCount != count) {
      _replace(post.copyWith(commentCount: count));
    }
  }

  /// An edited comment changes no count; lists of "my comments" refetch.
  void commentEdited() => _changed();

  /// New post from the composer goes to the top (below pinned posts). Posts
  /// held for review never reach the feed.
  void prepend(Post post) {
    _changed();
    final current = _current;
    if (current == null || !post.isPublished) return;
    if (!current.filter.matches(post)) return;
    final pinned = current.posts.where((p) => p.isPinned).toList();
    final rest = current.posts.where((p) => !p.isPinned).toList();
    state = AsyncData(current.copyWith(posts: [...pinned, post, ...rest]));
  }

  /// After the author edits a post: still published → updated in place;
  /// held for review → leaves the feed.
  void postUpdated(Post post) {
    _changed();
    final current = _current;
    if (current == null || current.byId(post.id) == null) return;
    if (post.isPublished) {
      _replace(post);
    } else {
      _drop(post.id);
    }
  }

  /// Author only; throws (and keeps the post) on failure.
  Future<void> deletePost(Post post) async {
    await _api.deletePost(post.id);
    _changed();
    _drop(post.id);
  }

  void _drop(String postId) {
    final current = _current;
    if (current == null) return;
    state = AsyncData(current.copyWith(
        posts: current.posts.where((p) => p.id != postId).toList()));
  }

  /// Called by the post detail while it polls the AI pipeline.
  void videoStatusChanged(String videoId, VideoAiStatus status) {
    final current = _current;
    if (current == null) return;
    for (final p in current.posts) {
      if (p.videoId == videoId && p.videoStatus != status) {
        _replace(p.copyWith(videoStatus: status));
      }
    }
  }
}
