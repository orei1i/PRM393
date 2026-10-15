// lib/features/community/presentation/screens/comments_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/author_summary.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/community_api_service.dart';
import '../../domain/entities/post.dart';
import '../controllers/feed_controller.dart';
import '../post_actions.dart';
import '../widgets/comment_tile.dart';

/// Full-screen thread: post header, comments, and a composer pinned above
/// the keyboard. Guests read freely; the composer asks them to sign in.
class CommentsScreen extends ConsumerStatefulWidget {
  const CommentsScreen({
    super.key,
    required this.post,
    this.onAdded,
    this.onRemoved,
    this.onEdited,
    this.autofocus = false,
  });

  final Post post;

  /// Called after the server confirms a new comment.
  final ValueChanged<Comment>? onAdded;

  /// Called after the member deletes / edits one of their comments.
  final ValueChanged<Comment>? onRemoved;
  final ValueChanged<Comment>? onEdited;

  /// Focus the composer on open ("Viết bình luận đầu tiên").
  final bool autofocus;

  static Route<void> route(
    Post post, {
    ValueChanged<Comment>? onAdded,
    ValueChanged<Comment>? onRemoved,
    ValueChanged<Comment>? onEdited,
    bool autofocus = false,
  }) =>
      MaterialPageRoute<void>(
        builder: (_) => CommentsScreen(
          post: post,
          onAdded: onAdded,
          onRemoved: onRemoved,
          onEdited: onEdited,
          autofocus: autofocus,
        ),
      );

  @override
  ConsumerState<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends ConsumerState<CommentsScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  List<Comment>? _comments;
  Object? _error;
  bool _sending = false;

  /// Own comment being edited in the composer.
  Comment? _editing;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !ref.read(sessionControllerProvider).isGuest) {
          _focus.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls to the comment just sent. Long threads build their tiles lazily,
  /// so the end is only exact once the last ones exist: jump until it holds.
  void _revealLatest([int attempts = 5]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients || attempts == 0) return;
      final end = _scroll.position.maxScrollExtent;
      if (_scroll.offset >= end) return;
      _scroll.jumpTo(end);
      _revealLatest(attempts - 1);
    });
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

  void _snack(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  /// Guests tap the (read-only) composer: sign in, then type.
  Future<void> _signInToComment() async {
    if (await ensureSignedIn(context, ref,
            reason: 'Đăng nhập để bình luận và hỏi tác giả.') &&
        mounted) {
      _focus.requestFocus();
    }
  }

  Future<void> _submit() async {
    if (_editing != null) return _saveEdit();
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
      author:
          AuthorSummary(id: me.userId ?? 'me', name: me.displayName ?? 'Bạn'),
      text: text,
      createdAt: DateTime.now(),
      pending: true,
      postId: widget.post.id,
    );
    setState(() {
      _sending = true;
      _comments = [...?_comments, pending];
      _input.clear();
    });
    _revealLatest();

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
      _snack(describeError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startEdit(Comment comment) {
    setState(() {
      _editing = comment;
      _input.text = comment.text;
    });
    _focus.requestFocus();
  }

  void _cancelEdit() {
    setState(() {
      _editing = null;
      _input.clear();
    });
    _focus.unfocus();
  }

  Future<void> _saveEdit() async {
    final editing = _editing!;
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (text == editing.text) return _cancelEdit();
    setState(() => _sending = true);
    try {
      final saved = (await ref
              .read(communityApiProvider)
              .updateComment(widget.post.id, editing.id, text))
          .toEntity();
      ref.read(feedControllerProvider.notifier).commentEdited();
      widget.onEdited?.call(saved);
      if (!mounted) return;
      setState(() {
        _comments = [
          for (final c in _comments ?? const <Comment>[])
            c.id == saved.id ? saved : c
        ];
        _editing = null;
        _input.clear();
      });
      _focus.unfocus();
    } catch (e) {
      if (mounted) _snack(describeError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(Comment comment) async {
    final deleted = await PostActions.deleteComment(context, ref,
        postId: widget.post.id, commentId: comment.id);
    if (!deleted) return;
    widget.onRemoved?.call(comment);
    if (!mounted) return;
    setState(() {
      _comments = _comments?.where((c) => c.id != comment.id).toList();
      if (_editing?.id == comment.id) {
        _editing = null;
        _input.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final comments = _comments;
    final session = ref.watch(sessionControllerProvider);
    final me = session.isGuest ? null : session.userId;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Bình luận'),
            const SizedBox(width: 8),
            if (comments != null)
              Text('${comments.length}',
                  style: context.textStyles.titleLarge
                      ?.copyWith(color: context.vl.muted)),
          ],
        ),
      ),
      body: Column(
        children: [
          _PostHeader(post: widget.post),
          const Divider(height: 1),
          Expanded(
            child: switch ((comments, _error)) {
              (_, final Object error) => Center(
                  child: SingleChildScrollView(
                      child: ErrorStateView(error: error, onRetry: _load))),
              (null, _) => const Center(child: CircularProgressIndicator()),
              (final List<Comment> list, _) when list.isEmpty => const Center(
                  child: SingleChildScrollView(
                    child: EmptyStateView(
                      icon: Icons.forum_outlined,
                      title: 'Chưa có bình luận',
                      message:
                          'Hãy là người đầu tiên hỏi hoặc góp ý cho tác giả.',
                    ),
                  ),
                ),
              (final List<Comment> list, _) => ListView.separated(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (_, i) {
                    final c = list[i];
                    final own = me != null && c.author.id == me;
                    return CommentTile(
                      comment: c,
                      onEdit: own ? () => _startEdit(c) : null,
                      onDelete: own ? () => _delete(c) : null,
                    );
                  },
                ),
            },
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: _Composer(
              controller: _input,
              focusNode: _focus,
              editing: _editing != null,
              sending: _sending,
              isGuest: session.isGuest,
              onSubmit: _submit,
              onCancelEdit: _cancelEdit,
              onGuestTap: _signInToComment,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostHeader extends StatelessWidget {
  const _PostHeader({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          UserAvatar(
              name: post.author.name,
              size: 32,
              verified: post.author.isVerifiedChef),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post.author.name,
                    style: context.textStyles.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (post.title.isNotEmpty)
                  Text(
                    post.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: context.vl.muted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.editing,
    required this.sending,
    required this.isGuest,
    required this.onSubmit,
    required this.onCancelEdit,
    required this.onGuestTap,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool editing;
  final bool sending;
  final bool isGuest;
  final VoidCallback onSubmit;
  final VoidCallback onCancelEdit;
  final VoidCallback onGuestTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (editing)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Row(
              children: [
                Icon(Icons.edit_outlined,
                    size: 16, color: context.colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Đang sửa bình luận',
                      style: context.textStyles.labelLarge
                          ?.copyWith(color: context.colors.primary)),
                ),
                TextButton(onPressed: onCancelEdit, child: const Text('Huỷ')),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  readOnly: isGuest,
                  onTap: isGuest ? onGuestTap : null,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 500,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSubmit(),
                  decoration: InputDecoration(
                    hintText:
                        isGuest ? 'Đăng nhập để bình luận…' : 'Viết bình luận…',
                    counterText: '',
                    border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24))),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    isDense: true,
                  ),
                ),
              ),
              IconButton.filled(
                tooltip: editing ? 'Lưu' : 'Gửi',
                onPressed: sending ? null : (isGuest ? onGuestTap : onSubmit),
                icon: Icon(editing ? Icons.check_rounded : Icons.send_rounded),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
