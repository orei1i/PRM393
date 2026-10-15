// lib/features/profile/presentation/screens/my_posts_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/state_views.dart';
import '../../../community/domain/entities/post.dart';
import '../../../community/presentation/post_actions.dart';
import '../../../community/presentation/screens/post_detail_screen.dart';
import '../../../community/presentation/widgets/feed_skeleton.dart';
import '../../../community/presentation/widgets/post_card.dart';
import '../../../video/presentation/screens/video_detail_screen.dart';
import '../controllers/profile_controller.dart';

/// "Bài viết của tôi" / "Đã lưu" — includes my videos still being processed by AI.
class MyPostsScreen extends StatelessWidget {
  const MyPostsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  static Route<void> route({int initialTab = 0}) => MaterialPageRoute<void>(
      builder: (_) => MyPostsScreen(initialTab: initialTab));

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nội dung của tôi'),
          bottom: const TabBar(
              tabs: [Tab(text: 'Bài của tôi'), Tab(text: 'Đã lưu')]),
        ),
        body: TabBarView(
          children: [
            _PostList(
              provider: myPostsProvider,
              emptyTitle: 'Bạn chưa đăng bài nào',
              emptyMessage: 'Chia sẻ công thức hoặc video ở tab Trang chủ.',
            ),
            _PostList(
              provider: savedPostsProvider,
              emptyTitle: 'Chưa lưu bài nào',
              emptyMessage:
                  'Chạm biểu tượng dấu trang trên bài viết để lưu lại.',
            ),
          ],
        ),
      ),
    );
  }
}

class _PostList extends ConsumerWidget {
  const _PostList(
      {required this.provider,
      required this.emptyTitle,
      required this.emptyMessage});

  final FutureProvider<List<Post>> provider;
  final String emptyTitle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(provider);
    return switch (async) {
      AsyncData(:final value) when value.isEmpty => Center(
          child: EmptyStateView(
              icon: Icons.article_outlined,
              title: emptyTitle,
              message: emptyMessage),
        ),
      AsyncData(:final value) => RefreshIndicator(
          onRefresh: () => ref.refresh(provider.future),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: value.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final post = value[i];
              return PostCard(
                post: post,
                onOpen: () =>
                    Navigator.of(context).push(PostDetailScreen.route(post)),
                onOpenVideo: post.videoId == null
                    ? null
                    : () => Navigator.of(context).push(
                        VideoDetailScreen.route(post.videoId!, post: post)),
                onLike: () async {
                  await PostActions.toggleLike(context, ref, post);
                  if (context.mounted) ref.invalidate(provider);
                },
                onSave: () async {
                  await PostActions.toggleSave(context, ref, post);
                  if (!context.mounted) return;
                  ref
                    ..invalidate(savedPostsProvider)
                    ..invalidate(myPostsProvider);
                },
                onComment: () => PostActions.openComments(
                  context,
                  post,
                  onAdded: (_) {
                    if (context.mounted) ref.invalidate(provider);
                  },
                ),
              );
            },
          ),
        ),
      AsyncError(:final error) => Center(
          child: ErrorStateView(
              error: error, onRetry: () => ref.invalidate(provider))),
      _ => const SingleChildScrollView(
          padding: EdgeInsets.only(top: 16), child: FeedSkeleton()),
    };
  }
}
