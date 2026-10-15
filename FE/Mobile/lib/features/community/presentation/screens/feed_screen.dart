// lib/features/community/presentation/screens/feed_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/floating_bar_clearance.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../ads/presentation/controllers/ads_controller.dart';
import '../../../ads/presentation/widgets/sponsored_store_card.dart';
import '../../../reels/presentation/controllers/reels_controller.dart';
import '../../../reels/presentation/widgets/reels_strip.dart';
import '../../../restaurant/presentation/screens/restaurant_nearby_screen.dart';
import '../../../search/presentation/screens/search_screen.dart';
import '../../../video/presentation/screens/video_detail_screen.dart';
import '../../domain/entities/post.dart';
import '../controllers/feed_controller.dart';
import '../post_actions.dart';
import '../widgets/feed_filter_chips.dart';
import '../widgets/feed_skeleton.dart';
import '../widgets/post_card.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';

/// Tab "Trang chủ": community feed (recipes, videos with AI summary, Q&A),
/// a "Reels" strip of short videos near the top, and a sponsored store card
/// ("Được tài trợ") after every [adEvery] posts. The app bar opens search
/// and "Quán chay gần bạn". Guests can read everything; actions ask for
/// sign-in.
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
    ref
      ..invalidate(reelsProvider)
      ..invalidate(feedAdsProvider);
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
        reason: 'Đăng nhập để chia sẻ công thức, video và câu hỏi.')) {
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
          created.type == PostType.video
              ? 'Đã đăng. AI đang tóm tắt video, bạn sẽ thấy kết quả sau ít phút.'
              : 'Đã đăng bài viết.',
        ),
      ),
    );
  }

  void _openPost(Post post) =>
      Navigator.of(context).push(PostDetailScreen.route(post));

  void _openVideo(Post post) {
    final videoId = post.videoId;
    if (videoId == null) return _openPost(post);
    Navigator.of(context).push(VideoDetailScreen.route(videoId, post: post));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(feedControllerProvider);
    final filter = async.hasValue ? async.requireValue.filter : null;

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
              title: Row(
                children: [
                  Icon(Icons.eco_rounded, color: context.colors.primary),
                  const SizedBox(width: 8),
                  const Text('VeganLife'),
                ],
              ),
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
                IconButton(
                  tooltip: 'Tạo bài viết',
                  onPressed: _compose,
                  icon: const Icon(Icons.add_box_outlined),
                ),
                const SizedBox(width: 4),
              ],
            ),
            SliverToBoxAdapter(child: _ComposerPrompt(onTap: _compose)),
            // Short videos: with "Tất cả" and "Video" only.
            if (filter == null || filter == PostType.video)
              const SliverToBoxAdapter(child: ReelsStrip()),
            SliverToBoxAdapter(
              child: FeedFilterChips(
                selected: filter,
                onSelected: (type) =>
                    ref.read(feedControllerProvider.notifier).setFilter(type),
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
    // No ads while they load or when they fail: the feed never waits on them.
    final slots = interleaveAds(
        feed.posts, ref.watch(feedAdsProvider).valueOrNull ?? const []);
    return [
      // Full-width posts separated by a surface-tone band.
      SliverPadding(
        padding: const EdgeInsets.only(top: 4),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final slot = slots[i];
              if (slot is AdSlot<Post>) {
                final ad = slot.ad;
                return Column(
                  key: ValueKey('ad-${ad.id}'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PostListGap(),
                    SponsoredStoreCard(ad: ad),
                  ],
                );
              }
              final post = (slot as PostSlot<Post>).post;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const PostListGap(),
                  PostCard(
                    key: ValueKey(post.id),
                    post: post,
                    onOpen: () => _openPost(post),
                    onOpenVideo: () => _openVideo(post),
                    onLike: () => PostActions.toggleLike(context, ref, post),
                    onSave: () => PostActions.toggleSave(context, ref, post),
                    onComment: () => PostActions.openComments(context, post),
                    onReport: () => PostActions.report(context, ref, post),
                  ),
                ],
              );
            },
            childCount: slots.length,
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

class _ComposerPrompt extends ConsumerWidget {
  const _ComposerPrompt({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name =
        ref.watch(sessionControllerProvider.select((s) => s.displayName));
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
                name == null
                    ? 'Chia sẻ món chay của bạn…'
                    : 'Hôm nay $name nấu món gì?',
                style: context.textStyles.bodyLarge
                    ?.copyWith(color: context.vl.muted),
              ),
            ),
            Icon(Icons.videocam_outlined, color: context.vl.ai),
            const SizedBox(width: 10),
            Icon(Icons.restaurant_menu_rounded, color: context.colors.primary),
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
