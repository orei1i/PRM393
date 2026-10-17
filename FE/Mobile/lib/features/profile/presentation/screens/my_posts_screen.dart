// lib/features/profile/presentation/screens/my_posts_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../community/data/community_api_service.dart';
import '../../../community/domain/entities/post.dart';
import '../../../community/presentation/controllers/my_comments_provider.dart';
import '../../../community/presentation/post_actions.dart';
import '../../../community/presentation/screens/post_detail_screen.dart';
import '../../../community/presentation/widgets/feed_skeleton.dart';
import '../../../community/presentation/widgets/post_card.dart';
import '../../../community/presentation/widgets/post_status_banner.dart';
import '../controllers/profile_controller.dart';

/// "Bài của tôi" (every status, with the review banner) · "Đã lưu" ·
/// "Bình luận". Includes my videos still being processed by AI.
class MyPostsScreen extends StatelessWidget {
  const MyPostsScreen({super.key, this.initialTab = 0, this.initialStatus});

  /// 0 = Bài của tôi, 1 = Đã lưu, 2 = Bình luận.
  final int initialTab;

  /// Pre-selected filter on "Bài của tôi"; `null` = Tất cả.
  final PostStatus? initialStatus;

  static Route<void> route({int initialTab = 0, PostStatus? initialStatus}) =>
      MaterialPageRoute<void>(
          builder: (_) => MyPostsScreen(
              initialTab: initialTab, initialStatus: initialStatus));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nội dung của tôi'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Bài của tôi'),
            Tab(text: 'Đã lưu'),
            Tab(text: 'Bình luận'),
          ]),
        ),
        body: TabBarView(
          children: [
            _MyPostsTab(initialStatus: initialStatus),
            const _SavedTab(),
            const _MyCommentsTab(),
          ],
        ),
      ),
    );
  }
}

/// Bottom padding that keeps the last item clear of the home indicator.
EdgeInsets _listPadding(BuildContext context) =>
    EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom);

/// Full-width posts (like the feed) need no side padding.
EdgeInsets _postListPadding(BuildContext context) =>
    EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom);

Widget _postCard(BuildContext context, WidgetRef ref, Post post) {
  // Likes, saves and comments bump communityRevisionProvider, which these
  // lists watch: no manual refetch needed. Video and recipe posts open the
  // same post detail.
  void open([PostDetailEntry entry = PostDetailEntry.top]) =>
      Navigator.of(context).push(PostDetailScreen.route(post, entry: entry));
  return PostCard(
    post: post,
    onOpen: open,
    onComment: () => open(PostDetailEntry.writeComment),
    onOpenComments: () => open(PostDetailEntry.comments),
    onLike: () => PostActions.toggleLike(context, ref, post),
    onSave: () => PostActions.toggleSave(context, ref, post),
  );
}

// ------------------------------------------------------------ my posts --

class _MyPostsTab extends ConsumerStatefulWidget {
  const _MyPostsTab({this.initialStatus});

  final PostStatus? initialStatus;

  @override
  ConsumerState<_MyPostsTab> createState() => _MyPostsTabState();
}

class _MyPostsTabState extends ConsumerState<_MyPostsTab> {
  late PostStatus? _filter = widget.initialStatus;

  /// Refetches while one of my videos is still in the AI pipeline, so its
  /// status chip moves on without pull-to-refresh.
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _syncPolling(List<Post> posts) {
    final processing = posts.any((p) => p.videoStatus?.isProcessing ?? false);
    if (!processing) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer(const Duration(seconds: 4), () {
      _poll = null;
      if (mounted) ref.invalidate(myPostsProvider);
    });
  }

  static const _empty = {
    null: (
      'Bạn chưa đăng bài nào',
      'Đăng công thức hoặc câu hỏi ở tab Trang chủ.'
    ),
    PostStatus.published: (
      'Chưa có bài nào đang hiển thị',
      'Bài đã đăng sẽ xuất hiện trên bảng tin và ở đây.'
    ),
    PostStatus.pending: (
      'Không có bài nào chờ duyệt',
      'Bài bị AI gắn cờ sẽ chờ Ban quản trị xem xét ở đây.'
    ),
    PostStatus.rejected: (
      'Không có bài bị từ chối',
      'Mọi bài của bạn đều đạt tiêu chuẩn cộng đồng.'
    ),
  };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myPostsProvider);
    if (!async.hasValue) {
      if (async.hasError) {
        return Center(
          child: SingleChildScrollView(
            child: ErrorStateView(
                error: async.error!,
                onRetry: () => ref.invalidate(myPostsProvider)),
          ),
        );
      }
      return const SingleChildScrollView(
          padding: EdgeInsets.only(top: 16), child: FeedSkeleton());
    }

    final posts = async.requireValue;
    _syncPolling(posts);
    final counts = {
      null: posts.length,
      for (final s in PostStatus.values)
        s: posts.where((p) => p.status == s).length,
    };
    final visible = _filter == null
        ? posts
        : posts.where((p) => p.status == _filter).toList();
    final (emptyTitle, emptyMessage) = _empty[_filter]!;

    return RefreshIndicator(
      onRefresh: () => ref.refresh(myPostsProvider.future),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: _postListPadding(context).copyWith(top: 12),
        children: [
          _StatusFilterChips(
            selected: _filter,
            counts: counts,
            onSelected: (s) => setState(() => _filter = s),
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            EmptyStateView(
                icon: Icons.article_outlined,
                title: emptyTitle,
                message: emptyMessage)
          else
            for (final post in visible)
              Column(
                key: ValueKey(post.id),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PostListGap(),
                  if (!post.isPublished)
                    ColoredBox(
                      color: context.colors.surface,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: PostStatusBanner(
                          post: post,
                          onResubmit: () =>
                              PostActions.edit(context, ref, post),
                        ),
                      ),
                    ),
                  _postCard(context, ref, post),
                ],
              ),
          if (visible.isNotEmpty) const PostListGap(),
        ],
      ),
    );
  }
}

/// Tất cả · Đã đăng · Chờ duyệt · Bị từ chối, with counts. Scrolls sideways
/// when the labels don't fit (large text).
class _StatusFilterChips extends StatelessWidget {
  const _StatusFilterChips(
      {required this.selected, required this.counts, required this.onSelected});

  final PostStatus? selected;
  final Map<PostStatus?, int> counts;
  final ValueChanged<PostStatus?> onSelected;

  static const _options = <(PostStatus?, String)>[
    (null, 'Tất cả'),
    (PostStatus.published, 'Đã đăng'),
    (PostStatus.pending, 'Chờ duyệt'),
    (PostStatus.rejected, 'Bị từ chối'),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (final (i, (status, label)) in _options.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            ChoiceChip(
              label: Text('$label (${counts[status] ?? 0})'),
              selected: selected == status,
              onSelected: (_) => onSelected(status),
            ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- saved --

class _SavedTab extends ConsumerWidget {
  const _SavedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(savedPostsProvider);
    if (!async.hasValue) {
      if (async.hasError) {
        return Center(
          child: SingleChildScrollView(
            child: ErrorStateView(
                error: async.error!,
                onRetry: () => ref.invalidate(savedPostsProvider)),
          ),
        );
      }
      return const SingleChildScrollView(
          padding: EdgeInsets.only(top: 16), child: FeedSkeleton());
    }
    final posts = async.requireValue;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(savedPostsProvider.future),
      child: posts.isEmpty
          ? const SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: EmptyStateView(
                icon: Icons.bookmark_border_rounded,
                title: 'Chưa lưu bài nào',
                message: 'Chạm biểu tượng dấu trang trên bài viết để lưu lại.',
              ),
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: _postListPadding(context),
              itemCount: posts.length + 1,
              itemBuilder: (context, i) => i == posts.length
                  ? const PostListGap()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const PostListGap(),
                        _postCard(context, ref, posts[i]),
                      ],
                    ),
            ),
    );
  }
}

// ------------------------------------------------------------ comments --

class _MyCommentsTab extends ConsumerStatefulWidget {
  const _MyCommentsTab();

  @override
  ConsumerState<_MyCommentsTab> createState() => _MyCommentsTabState();
}

class _MyCommentsTabState extends ConsumerState<_MyCommentsTab> {
  /// Comment whose post is being fetched before opening.
  String? _openingId;

  Future<void> _open(MyComment comment) async {
    if (_openingId != null) return;
    setState(() => _openingId = comment.id);
    try {
      final post =
          (await ref.read(communityApiProvider).getPost(comment.postId))
              .toEntity();
      if (mounted) {
        // Straight to the comment, tinted for a moment.
        await Navigator.of(context).push(PostDetailScreen.route(
          post,
          entry: PostDetailEntry.comments,
          highlightCommentId: comment.id,
          highlightParentId: comment.parentId,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myCommentsProvider);
    if (!async.hasValue) {
      if (async.hasError) {
        return Center(
          child: SingleChildScrollView(
            child: ErrorStateView(
                error: async.error!,
                onRetry: () => ref.invalidate(myCommentsProvider)),
          ),
        );
      }
      return const _CommentsSkeleton();
    }
    final comments = async.requireValue;
    return RefreshIndicator(
      onRefresh: () => ref.refresh(myCommentsProvider.future),
      child: comments.isEmpty
          ? const SingleChildScrollView(
              physics: AlwaysScrollableScrollPhysics(),
              child: EmptyStateView(
                icon: Icons.forum_outlined,
                title: 'Chưa có bình luận nào',
                message: 'Bình luận của bạn trên các bài viết sẽ hiện ở đây.',
              ),
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: _listPadding(context),
              itemCount: comments.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final c = comments[i];
                return _MyCommentCard(
                  key: ValueKey(c.id),
                  comment: c,
                  opening: _openingId == c.id,
                  onOpen: () => _open(c),
                  onEdit: () =>
                      PostActions.editCommentInDialog(context, ref, c),
                  onDelete: () => PostActions.deleteComment(context, ref,
                      postId: c.postId, commentId: c.id),
                );
              },
            ),
    );
  }
}

enum _MyCommentAction { edit, delete }

class _MyCommentCard extends StatelessWidget {
  const _MyCommentCard({
    super.key,
    required this.comment,
    required this.opening,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  final MyComment comment;
  final bool opening;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    return VLCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.article_outlined, size: 18, color: context.vl.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  comment.postTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.textStyles.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              PopupMenuButton<_MyCommentAction>(
                tooltip: 'Tuỳ chọn bình luận',
                icon: Icon(Icons.more_horiz_rounded, color: context.vl.muted),
                onSelected: (a) => switch (a) {
                  _MyCommentAction.edit => onEdit(),
                  _MyCommentAction.delete => onDelete(),
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _MyCommentAction.edit,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Sửa'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _MyCommentAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline_rounded,
                          color: context.colors.error),
                      title: Text('Xoá',
                          style: TextStyle(color: context.colors.error)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(comment.text, style: context.textStyles.bodyMedium),
          ),
          const SizedBox(height: 6),
          Text(
            comment.isEdited
                ? '${relativeTime(comment.createdAt)} · (đã sửa)'
                : relativeTime(comment.createdAt),
            style: muted,
          ),
          if (opening) ...[
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommentsSkeleton extends StatelessWidget {
  const _CommentsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (var i = 0; i < 4; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: VLCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 200, height: 14),
                    SizedBox(height: 8),
                    SkeletonBox(height: 12),
                    SizedBox(height: 6),
                    SkeletonBox(width: 90, height: 10),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
