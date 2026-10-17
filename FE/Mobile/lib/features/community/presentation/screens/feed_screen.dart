// lib/features/community/presentation/screens/feed_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/floating_bar_clearance.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../reels/presentation/controllers/reels_controller.dart';
import '../../../reels/presentation/widgets/reels_strip.dart';
import '../../../restaurant/presentation/screens/restaurant_nearby_screen.dart';
import '../../../search/presentation/screens/search_screen.dart';
import '../../domain/entities/post.dart';
import '../controllers/feed_controller.dart';
import '../post_actions.dart';
import '../widgets/feed_filter_chips.dart';
import '../widgets/feed_skeleton.dart';
import '../widgets/post_card.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';

/// Tab "Trang chủ": community feed (Công thức and Hỏi đáp, some with a photo
/// or video), the "Bếp nhanh" strip near the top (with "Tất cả" and "Có video"),
/// and the composer prompt "Hôm nay … nấu món gì?" (the only way to post).
/// The app bar opens search and "Quán chay gần bạn". No sponsored cards.
/// Guests read everything; actions ask for sign-in.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) {
        ref.read(feedControllerProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(reelsProvider);
    try {
      await ref.read(feedControllerProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Chưa làm mới được. ${describeError(e)}')));
      }
    }
  }

  Future<void> _compose() async {
    if (!await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để chia sẻ công thức và câu hỏi với cộng đồng.')) {
      return;
    }
    if (!mounted) return;
    final created =
        await Navigator.of(context).push<Post>(CreatePostScreen.route());
    if (created == null || !mounted) return;
    ref.read(feedControllerProvider.notifier).prepend(created);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          created.videoId != null
              ? 'Đã đăng. AI đang tóm tắt video, bạn sẽ thấy kết quả sau ít phút.'
              : 'Đã đăng bài viết.',
        ),
      ),
    );
  }

  void _open(Post post, [PostDetailEntry entry = PostDetailEntry.top]) =>
      Navigator.of(context).push(PostDetailScreen.route(post, entry: entry));

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(feedControllerProvider);
    final filter = async.hasValue ? async.requireValue.filter : FeedFilter.all;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              titleSpacing: 16,
              title: const VeganLifeLogo(),
              actions: [
                IconButton(
                  tooltip: 'Tìm kiếm',
                  onPressed: () =>
                      Navigator.of(context).push(SearchScreen.route()),
                  icon: const Icon(Icons.search_rounded),
                ),
                IconButton(
                  tooltip: 'Quán chay gần bạn',
                  onPressed: () => Navigator.of(context)
                      .push(RestaurantNearbyScreen.route()),
                  icon: const Icon(Icons.storefront_outlined),
                ),
                const SizedBox(width: 4),
              ],
            ),
            SliverToBoxAdapter(child: _ComposerPrompt(onTap: _compose)),
            if (filter.showsReels)
              const SliverToBoxAdapter(child: ReelsStrip()),
            SliverToBoxAdapter(
              child: FeedFilterChips(
                selected: filter,
                onSelected: (f) =>
                    ref.read(feedControllerProvider.notifier).setFilter(f),
              ),
            ),
            ...switch (async) {
              AsyncData(:final value) => _content(value),
              AsyncError(:final error) => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: ErrorStateView(
                          error: error,
                          onRetry: () =>
                              ref.invalidate(feedControllerProvider)),
                    ),
                  ),
                ],
              _ => [const SliverToBoxAdapter(child: FeedSkeleton())],
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _content(FeedState feed) {
    if (feed.posts.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: EmptyStateView(
              icon: Icons.dynamic_feed_outlined,
              title: 'Chưa có bài nào ở mục này',
              message: 'Hãy chia sẻ món chay đầu tiên của bạn với cộng đồng.',
              actionLabel: 'Tạo bài viết',
              onAction: _compose,
            ),
          ),
        ),
      ];
    }
    return [
      // Full-width posts separated by a surface-tone band.
      SliverPadding(
        padding: const EdgeInsets.only(top: 4),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final post = feed.posts[i];
              return Column(
                key: ValueKey(post.id),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PostListGap(),
                  PostCard(
                    post: post,
                    onOpen: () => _open(post),
                    onComment: () => _open(post, PostDetailEntry.writeComment),
                    onOpenComments: () => _open(post, PostDetailEntry.comments),
                    onLike: () => PostActions.toggleLike(context, ref, post),
                    onSave: () => PostActions.toggleSave(context, ref, post),
                    onReport: () => PostActions.report(context, ref, post),
                  ),
                ],
              );
            },
            childCount: feed.posts.length,
          ),
        ),
      ),
      const SliverToBoxAdapter(child: PostListGap()),
      SliverToBoxAdapter(child: _Footer(feed: feed)),
      // Bottom breathing room: clears the shell's floating bar.
      SliverToBoxAdapter(
          child: SizedBox(height: floatingBarClearance(context))),
    ];
  }
}

/// "Hôm nay {tên} nấu món gì?" (guests: "Hôm nay bạn nấu món gì?"): opens
/// Tạo bài viết; guests are asked to sign in first.
class _ComposerPrompt extends ConsumerWidget {
  const _ComposerPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(sessionControllerProvider
        .select((s) => s.isGuest ? null : s.displayName));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: VLCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            UserAvatar(name: name ?? 'Khách', size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Hôm nay ${name ?? 'bạn'} nấu món gì?',
                style: context.textStyles.bodyLarge
                    ?.copyWith(color: context.vl.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.feed});

  final FeedState feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (feed.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (feed.loadMoreError != null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: TextButton.icon(
            onPressed: () =>
                ref.read(feedControllerProvider.notifier).loadMore(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Chưa tải thêm được — thử lại'),
          ),
        ),
      );
    }
    if (!feed.hasMore) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'Bạn đã xem hết bài mới',
            style:
                context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
          ),
        ),
      );
    }
    return const SizedBox(height: 16);
  }
}
