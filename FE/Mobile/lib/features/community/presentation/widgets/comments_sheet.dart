// lib/features/community/presentation/widgets/comments_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/models/author_summary.dart';
import '../../data/community_api_service.dart';
import '../../domain/entities/post.dart';
import '../controllers/feed_controller.dart';

/// Bottom-sheet thread with an optimistic composer.
class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({super.key, required this.post, this.onAdded});

  final Post post;

  /// Called after the server confirms a new comment.
  final ValueChanged<Comment>? onAdded;

  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  final _input = TextEditingController();
  List<Comment>? _comments;
  Object? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final items =
          await ref.read(communityApiProvider).getComments(widget.post.id);
      if (mounted) {
        setState(() => _comments = items.map((c) => c.toEntity()).toList());
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (!await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để bình luận và hỏi tác giả.')) {
      return;
    }
    if (!mounted) return;

    final me = ref.read(sessionControllerProvider);
    final pending = Comment(
      id: 'pending_${DateTime.now().microsecondsSinceEpoch}',
      author: AuthorSummary(id: 'me', name: me.displayName ?? 'Bạn'),
      text: text,
      createdAt: DateTime.now(),
      pending: true,
    );
    setState(() {
      _sending = true;
      _comments = [...?_comments, pending];
      _input.clear();
    });

    try {
      final saved =
          await ref.read(communityApiProvider).addComment(widget.post.id, text);
      ref.read(feedControllerProvider.notifier).commentAdded(widget.post.id);
      widget.onAdded?.call(saved.toEntity());
      if (!mounted) return;
      setState(() {
        _comments = [
          for (final c in _comments!) c.id == pending.id ? saved.toEntity() : c
        ];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _comments = _comments!.where((c) => c.id != pending.id).toList();
        _input.text = text;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final comments = _comments;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Text('Bình luận', style: context.textStyles.titleMedium),
                  const SizedBox(width: 8),
                  if (comments != null)
                    Text('${comments.length}',
                        style: context.textStyles.titleMedium
                            ?.copyWith(color: context.vl.muted)),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: switch ((comments, _error)) {
                (_, final Object error) =>
                  Center(child: ErrorStateView(error: error, onRetry: _load)),
                (null, _) => const Center(child: CircularProgressIndicator()),
                (final List<Comment> list, _) when list.isEmpty => const Center(
                    child: EmptyStateView(
                      icon: Icons.forum_outlined,
                      title: 'Chưa có bình luận',
                      message:
                          'Hãy là người đầu tiên hỏi hoặc góp ý cho tác giả.',
                    ),
                  ),
                (final List<Comment> list, _) => ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (_, i) => CommentTile(comment: list[i]),
                  ),
              },
            ),
            const Divider(),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 500,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Viết bình luận…',
                          counterText: '',
                          border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(24))),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          isDense: true,
                        ),
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Gửi',
                      onPressed: _sending ? null : _send,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CommentTile extends StatelessWidget {
  const CommentTile({super.key, required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: comment.pending ? 0.55 : 1,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UserAvatar(
              name: comment.author.name,
              size: 32,
              verified: comment.author.isVerifiedChef),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        comment.author.name,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      comment.pending
                          ? 'Đang gửi…'
                          : relativeTime(comment.createdAt),
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: context.vl.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.text, style: context.textStyles.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
