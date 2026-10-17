// lib/features/community/presentation/widgets/comments_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/post.dart';
import 'comment_thread.dart';

/// Reels "Bình luận": the post's thread and composer in a bottom sheet (85 %
/// of the screen), same paging, replies and actions as the post detail.
/// [onCountChanged] receives each change of the comment count. Resolves
/// when the sheet is closed.
Future<void> showCommentsSheet(BuildContext context, Post post,
        {ValueChanged<int>? onCountChanged}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => CommentsSheet(post: post, onCountChanged: onCountChanged),
    );

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({super.key, required this.post, this.onCountChanged});

  final Post post;
  final ValueChanged<int>? onCountChanged;

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet>
    with CommentSectionMixin {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    initComments(widget.post);
    comments.addListener(_onCommentsChanged);
    _scroll.addListener(_maybeLoadMore);
    comments.loadMore();
  }

  @override
  void dispose() {
    comments.removeListener(_onCommentsChanged);
    comments.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void onCommentCountChanged(int delta) => widget.onCountChanged?.call(delta);

  void _maybeLoadMore() {
    if (comments.loading || comments.error != null || !comments.hasMore) {
      return;
    }
    if (_scroll.hasClients && _scroll.position.extentAfter < 300) {
      comments.loadMore();
    }
  }

  void _onCommentsChanged() =>
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeLoadMore();
      });

  void _posted(Comment comment) {
    if (!comment.isReply && _scroll.hasClients) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(
        sessionControllerProvider.select((s) => s.isGuest ? null : s.userId));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: ListenableBuilder(
                      listenable: comments,
                      builder: (context, _) => Text(
                          'Bình luận (${comments.total})',
                          style: context.textStyles.titleLarge),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
                child: CommentThreadList(
                  controller: comments,
                  currentUserId: me,
                  onReply: replyTo,
                  onEdit: editComment,
                  onDelete: deleteComment,
                  onMoreReplies: loadReplies,
                ),
              ),
            ),
            Divider(height: 1, color: context.vl.border),
            SafeArea(
              top: false,
              child: CommentComposer(
                key: composerKey,
                controller: comments,
                onPosted: _posted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
