// lib/features/community/presentation/screens/post_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../video/presentation/screens/video_detail_screen.dart';
import '../../data/community_api_service.dart';
import '../../domain/entities/post.dart';
import '../controllers/feed_controller.dart';
import '../post_actions.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/post_card.dart';
import '../widgets/video_status_chip.dart';

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.post});

  final Post post;

  static Route<void> route(Post post) =>
      MaterialPageRoute<void>(builder: (_) => PostDetailScreen(post: post));

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  late Post _post = widget.post;
  final _previewKey = GlobalKey<_CommentsPreviewState>();

  Future<void> _like() async {
    final before = _post;
    setState(() => _post = before.toggledLike());
    final result = await PostActions.toggleLike(context, ref, before);
    if (result == null && mounted) setState(() => _post = before);
  }

  Future<void> _save() async {
    final before = _post;
    setState(() => _post = before.toggledSave());
    final result = await PostActions.toggleSave(context, ref, before);
    if (result == null && mounted) setState(() => _post = before);
  }

  Future<void> _comments() => PostActions.openComments(
        context,
        _post,
        onAdded: (_) {
          if (!mounted) return;
          setState(() =>
              _post = _post.copyWith(commentCount: _post.commentCount + 1));
          _previewKey.currentState?.reload();
        },
      );

  void _openVideo() {
    final id = _post.videoId;
    if (id != null) {
      Navigator.of(context).push(VideoDetailScreen.route(id, post: _post));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prefer the feed's copy when it changes elsewhere (e.g. like from the list).
    final fromFeed = ref.watch(
      feedControllerProvider
          .select((s) => s.hasValue ? s.requireValue.byId(_post.id) : null),
    );
    final post = fromFeed ?? _post;

    return Scaffold(
      appBar: AppBar(
        title: Text(post.type.label),
        actions: [
          IconButton(
            tooltip: 'Báo cáo',
            onPressed: () => PostActions.report(context, ref, post),
            icon: const Icon(Icons.flag_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          PostAuthorRow(post: post),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(post.title,
                style: context.textStyles.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (post.hasCover)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: GestureDetector(
                onTap: post.type == PostType.video ? _openVideo : null,
                child: FoodCover(
                  seed: post.coverSeed,
                  imageUrl: post.imageUrl,
                  aspectRatio: 16 / 9,
                  borderRadius: BorderRadius.circular(16),
                  child: post.type == PostType.video
                      ? Stack(
                          children: [
                            const Center(
                              child: Icon(Icons.play_circle_fill_rounded,
                                  size: 64, color: Colors.white),
                            ),
                            if (post.videoStatus != null)
                              Positioned(
                                  left: 10,
                                  top: 10,
                                  child: VideoStatusChip(
                                      status: post.videoStatus!)),
                          ],
                        )
                      : null,
                ),
              ),
            ),
          if (post.type == PostType.video)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: VLCard(
                color: context.vl.aiContainer,
                borderColor: context.vl.aiBorder,
                onTap: _openVideo,
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, color: context.vl.ai),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Xem nguyên liệu và từng bước AI trích từ video',
                        style: context.textStyles.bodyMedium
                            ?.copyWith(color: context.vl.onAiContainer),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: context.vl.onAiContainer),
                  ],
                ),
              ),
            ),
          if (post.body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: SelectableText(post.body,
                  style: context.textStyles.bodyLarge?.copyWith(height: 1.55)),
            ),
          if (post.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in post.tags)
                    VLTag.neutral(context, dietTagLabel(t))
                ],
              ),
            ),
          const SizedBox(height: 6),
          PostActionsBar(
              post: post, onLike: _like, onComment: _comments, onSave: _save),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text('Bình luận', style: context.textStyles.titleMedium),
          ),
          _CommentsPreview(key: _previewKey, postId: post.id),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _comments,
              icon: const Icon(Icons.mode_comment_outlined),
              label: Text(post.commentCount == 0
                  ? 'Viết bình luận đầu tiên'
                  : 'Xem tất cả & bình luận'),
            ),
          ),
        ],
      ),
    );
  }
}

/// First three comments, loaded inline.
class _CommentsPreview extends ConsumerStatefulWidget {
  const _CommentsPreview({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<_CommentsPreview> createState() => _CommentsPreviewState();
}

class _CommentsPreviewState extends ConsumerState<_CommentsPreview> {
  late Future<List<Comment>> _future = _load();

  Future<List<Comment>> _load() async {
    final items =
        await ref.read(communityApiProvider).getComments(widget.postId);
    return items.map((c) => c.toEntity()).toList();
  }

  // Block body: an arrow would return the Future and trip setState's assert.
  void reload() => setState(() {
        _future = _load();
      });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Comment>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return ListTile(
            leading: const Icon(Icons.error_outline_rounded),
            title: const Text('Chưa tải được bình luận'),
            trailing:
                TextButton(onPressed: reload, child: const Text('Thử lại')),
          );
        }
        final items = snapshot.data ?? const <Comment>[];
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Chưa có bình luận nào.',
              style: context.textStyles.bodyMedium
                  ?.copyWith(color: context.vl.muted),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (final c in items.take(3))
                Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: CommentTile(comment: c)),
            ],
          ),
        );
      },
    );
  }
}
