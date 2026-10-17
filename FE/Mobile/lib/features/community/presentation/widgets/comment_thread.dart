// lib/features/community/presentation/widgets/comment_thread.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/author_summary.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../data/community_api_service.dart';
import '../../domain/entities/post.dart';
import '../controllers/comment_thread_controller.dart';
import '../controllers/feed_controller.dart';
import '../post_actions.dart';
import 'comment_tile.dart';

const _signInReason = 'Đăng nhập để bình luận và hỏi tác giả.';

/// Shared by the post detail and the Reels comments sheet: owns the
/// [CommentThreadController], the composer key, and the reply / edit /
/// delete handlers. The feed's copy of the post follows every count change.
mixin CommentSectionMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  late final CommentThreadController comments;
  final composerKey = GlobalKey<CommentComposerState>();

  /// Call from `initState`.
  void initComments(Post post) {
    // Read now: callbacks may run after this screen is gone.
    final feed = ref.read(feedControllerProvider.notifier);
    comments = CommentThreadController(
      api: ref.read(communityApiProvider),
      postId: post.id,
      initialCount: post.commentCount,
      // Only asked while the composer (so this screen) is on screen.
      me: () {
        final s = ref.read(sessionControllerProvider);
        return AuthorSummary(
            id: s.userId ?? 'me', name: s.displayName ?? 'Bạn');
      },
      onCountChanged: (delta) {
        feed.commentsChanged(post.id, delta);
        onCommentCountChanged(delta);
      },
      onEdited: feed.commentEdited,
    );
  }

  /// Override to follow the count ("Bình luận (N)", the reel's rail).
  void onCommentCountChanged(int delta) {}

  void snack(String message) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> replyTo(Comment comment) async =>
      composerKey.currentState?.reply(comment);

  void editComment(Comment comment) => composerKey.currentState?.edit(comment);

  Future<void> loadReplies(String commentId) async {
    try {
      await comments.loadReplies(commentId);
    } catch (e) {
      if (mounted) snack(describeError(e));
    }
  }

  /// "Xoá bình luận và N phản hồi?" → deletes after confirming.
  Future<void> deleteComment(Comment comment) async {
    final replies = comments.repliesGoingWith(comment);
    final ok = await PostActions.confirm(
      context,
      title: replies > 0
          ? 'Xoá bình luận và $replies phản hồi?'
          : 'Xoá bình luận?',
      message: replies > 0
          ? 'Bình luận và các phản hồi sẽ bị xoá vĩnh viễn.'
          : 'Bình luận sẽ bị xoá vĩnh viễn.',
    );
    if (!ok || !mounted) return;
    composerKey.currentState?.forget(comment.id);
    try {
      await comments.delete(comment);
      if (mounted) snack('Đã xoá bình luận');
    } catch (e) {
      if (mounted) snack(describeError(e));
    }
  }
}

/// The loaded threads (top-level comment, its replies indented, "Xem thêm N
/// phản hồi") and the paging footer: spinner, "Chưa tải được bình luận ·
/// Thử lại", or the empty message. Built in full (not lazily) so a comment
/// can be scrolled to; paging keeps it to what the member has scrolled.
class CommentThreadList extends StatelessWidget {
  const CommentThreadList({
    super.key,
    required this.controller,
    required this.currentUserId,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onMoreReplies,
    this.highlightId,
    this.keyFor,
  });

  final CommentThreadController controller;

  /// `null` for guests: nobody's comment is theirs.
  final String? currentUserId;
  final ValueChanged<Comment> onReply;
  final ValueChanged<Comment> onEdit;
  final ValueChanged<Comment> onDelete;
  final ValueChanged<String> onMoreReplies;
  final String? highlightId;

  /// A key for a tile the host wants to scroll to.
  final Key? Function(String commentId)? keyFor;

  Widget _tile(Comment c) {
    final own = currentUserId != null && c.author.id == currentUserId;
    return CommentTile(
      key: keyFor?.call(c.id) ?? ValueKey('comment-${c.id}'),
      comment: c,
      highlighted: c.id == highlightId,
      onReply: () => onReply(c),
      onEdit: own ? () => onEdit(c) : null,
      onDelete: own ? () => onDelete(c) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final t in c.threads)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _tile(t.comment),
                    if (t.replies.isNotEmpty || t.hiddenReplies > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 42, top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final r in t.replies)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: _tile(r),
                              ),
                            if (t.hiddenReplies > 0)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: t.loadingReplies
                                    ? const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: SizedBox.square(
                                            dimension: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2)),
                                      )
                                    : TextButton.icon(
                                        style: TextButton.styleFrom(
                                          visualDensity: VisualDensity.compact,
                                          foregroundColor: context.vl.muted,
                                        ),
                                        onPressed: () =>
                                            onMoreReplies(t.comment.id),
                                        icon: const Icon(
                                            Icons
                                                .subdirectory_arrow_right_rounded,
                                            size: 18),
                                        label: Text(
                                            'Xem thêm ${t.hiddenReplies} phản hồi'),
                                      ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            if (c.loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (c.error != null)
              Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: context.vl.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Chưa tải được bình luận',
                        style: context.textStyles.bodyMedium
                            ?.copyWith(color: context.vl.muted)),
                  ),
                  TextButton(
                      onPressed: c.loadMore, child: const Text('Thử lại')),
                ],
              )
            else if (c.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Chưa có bình luận nào. Hãy là người đầu tiên!',
                  style: context.textStyles.bodyMedium
                      ?.copyWith(color: context.vl.muted),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Pinned at the bottom: avatar, "Viết bình luận…", send. Shows "Đang trả
/// lời {tên} · Huỷ" / "Đang sửa bình luận · Huỷ" above the field. Guests
/// get the sign-in sheet on tap, then the field is focused.
class CommentComposer extends ConsumerStatefulWidget {
  const CommentComposer({
    super.key,
    required this.controller,
    this.focusNode,
    this.onPosted,
  });

  final CommentThreadController controller;
  final FocusNode? focusNode;

  /// After the server confirmed a new comment or reply (e.g. scroll to it).
  final ValueChanged<Comment>? onPosted;

  @override
  ConsumerState<CommentComposer> createState() => CommentComposerState();
}

class CommentComposerState extends ConsumerState<CommentComposer> {
  final _input = TextEditingController();
  final _fieldKey = GlobalKey();
  FocusNode? _ownFocus;
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  Comment? _replyTo;
  Comment? _editing;
  bool _sending = false;

  @override
  void dispose() {
    _input.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  bool get _isGuest => ref.read(sessionControllerProvider).isGuest;

  /// Focuses the field; guests sign in first. `true` when focused.
  Future<bool> focusInput() async {
    if (_isGuest &&
        !await ensureSignedIn(context, ref, reason: _signInReason)) {
      return false;
    }
    if (!mounted) return false;
    _showKeyboard();
    return true;
  }

  /// Focuses the field with the keyboard up, like tapping it.
  ///
  /// `FocusNode.requestFocus` does nothing for a field that already has
  /// focus, e.g. after sending a comment and closing the keyboard with Back:
  /// the field stays focused but the keyboard would not come back.
  /// [EditableTextState.requestKeyboard] reopens it in that case and
  /// requests focus otherwise.
  void _showKeyboard() {
    final editable = _editableText();
    if (editable != null) {
      editable.requestKeyboard();
    } else {
      _focus.requestFocus();
    }
  }

  EditableTextState? _editableText() {
    EditableTextState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        found = element.state as EditableTextState;
        return;
      }
      element.visitChildElements(visit);
    }

    _fieldKey.currentContext?.visitChildElements(visit);
    return found;
  }

  static String _mention(Comment comment) => '@${comment.author.name} ';

  void _caretToEnd() =>
      _input.selection = TextSelection.collapsed(offset: _input.text.length);

  /// "Trả lời": answers [comment]; a reply to a reply starts with "@Tên ".
  /// The caret goes to the end (after "@Tên ") and the keyboard opens.
  Future<void> reply(Comment comment) async {
    if (_isGuest &&
        !await ensureSignedIn(context, ref, reason: _signInReason)) {
      return;
    }
    if (!mounted) return;
    setState(() {
      // The text of a comment being edited is not a reply.
      if (_editing != null) _input.clear();
      _editing = null;
      // Switching to another reply: its "@Tên " replaces the previous one.
      final previous = _replyTo;
      if (previous != null && previous.isReply) {
        final old = _mention(previous);
        if (_input.text.startsWith(old)) {
          _input.text = _input.text.substring(old.length);
        }
      }
      _replyTo = comment;
      final mention = _mention(comment);
      if (comment.isReply && !_input.text.startsWith(mention)) {
        _input.text = '$mention${_input.text}';
      }
      _caretToEnd();
    });
    _showKeyboard();
  }

  /// "Sửa": the member's own comment goes into the field, caret at the end,
  /// keyboard up.
  void edit(Comment comment) {
    setState(() {
      _replyTo = null;
      _editing = comment;
      _input.text = comment.text;
      _caretToEnd();
    });
    _showKeyboard();
  }

  /// [commentId] was deleted: stop replying to / editing it.
  void forget(String commentId) {
    if (_editing?.id == commentId) {
      setState(() {
        _editing = null;
        _input.clear();
      });
    }
    if (_replyTo?.id == commentId || _replyTo?.parentId == commentId) {
      setState(() => _replyTo = null);
    }
  }

  void _cancel() {
    setState(() {
      if (_editing != null) _input.clear();
      _editing = null;
      _replyTo = null;
    });
    _focus.unfocus();
  }

  void _snack(String message) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (_isGuest) {
      if (!await focusInput()) return;
      if (!mounted) return;
    }
    final editing = _editing;
    if (editing != null) {
      if (text == editing.text) return _cancel();
      setState(() => _sending = true);
      try {
        await widget.controller.edit(editing, text);
        if (!mounted) return;
        setState(() {
          _editing = null;
          _input.clear();
        });
        _focus.unfocus();
      } catch (e) {
        if (mounted) _snack(describeError(e));
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
    }

    final replyTo = _replyTo;
    setState(() {
      _sending = true;
      _input.clear();
    });
    try {
      final saved = await widget.controller.add(text, replyTo: replyTo);
      if (!mounted) return;
      setState(() => _replyTo = null);
      widget.onPosted?.call(saved);
    } catch (e) {
      if (!mounted) return;
      // Keep what the member typed.
      setState(() => _input.text = text);
      _snack(describeError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final guest = session.isGuest;
    final replyTo = _replyTo;
    final editing = _editing != null;
    final banner = editing
        ? 'Đang sửa bình luận'
        : replyTo == null
            ? null
            : 'Đang trả lời ${replyTo.author.name}';
    return Material(
      color: context.colors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (banner != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  Icon(editing ? Icons.edit_outlined : Icons.reply_rounded,
                      size: 16, color: context.colors.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(banner,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.labelLarge
                            ?.copyWith(color: context.colors.primary)),
                  ),
                  TextButton(onPressed: _cancel, child: const Text('Huỷ')),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                UserAvatar(name: session.displayName ?? 'Khách', size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    key: _fieldKey,
                    controller: _input,
                    focusNode: _focus,
                    readOnly: guest,
                    onTap: guest ? focusInput : null,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 500,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: replyTo != null
                          ? 'Viết phản hồi…'
                          : 'Viết bình luận…',
                      counterText: '',
                      border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24))),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: editing ? 'Lưu bình luận' : 'Gửi',
                  onPressed: _sending ? null : (guest ? focusInput : _submit),
                  icon:
                      Icon(editing ? Icons.check_rounded : Icons.send_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
