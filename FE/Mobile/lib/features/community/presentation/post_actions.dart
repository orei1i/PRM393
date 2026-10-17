// lib/features/community/presentation/post_actions.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/vl_colors.dart';
import '../../../core/widgets/sign_in_sheet.dart';
import '../data/community_api_service.dart';
import '../domain/entities/post.dart';
import 'controllers/feed_controller.dart';
import 'screens/create_post_screen.dart';
import 'widgets/report_post_sheet.dart';

/// Shared like / save / report handlers for the feed card, the post detail
/// and Reels, plus the author's own edit / delete and the "Nội dung của tôi
/// › Bình luận" comment actions. Each returns the post as it should now be
/// displayed, or `null` when nothing changed (guest dismissed sign-in,
/// request failed). Comments themselves live in the post detail.
abstract final class PostActions {
  static Future<Post?> toggleLike(
      BuildContext context, WidgetRef ref, Post post) async {
    if (!await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để thích bài viết và theo dõi tác giả.')) {
      return null;
    }
    try {
      await ref
          .read(feedControllerProvider.notifier)
          .setLiked(post, liked: !post.likedByMe);
      return post.toggledLike();
    } catch (e) {
      if (context.mounted) _snack(context, describeError(e));
      return null;
    }
  }

  static Future<Post?> toggleSave(
      BuildContext context, WidgetRef ref, Post post) async {
    if (!await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để lưu công thức vào bộ sưu tập của bạn.')) {
      return null;
    }
    try {
      await ref
          .read(feedControllerProvider.notifier)
          .setSaved(post, saved: !post.savedByMe);
      if (context.mounted) {
        _snack(context, post.savedByMe ? 'Đã bỏ lưu' : 'Đã lưu vào mục Đã lưu');
      }
      return post.toggledSave();
    } catch (e) {
      if (context.mounted) _snack(context, describeError(e));
      return null;
    }
  }

  static Future<void> report(
      BuildContext context, WidgetRef ref, Post post) async {
    if (!await ensureSignedIn(context, ref,
        reason: 'Đăng nhập để gửi báo cáo cho đội kiểm duyệt.')) {
      return;
    }
    if (!context.mounted) return;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReportPostSheet(post: post),
    );
    if (sent == true && context.mounted) {
      _snack(
          context, 'Đã gửi báo cáo. Đội kiểm duyệt sẽ xem xét trong 24 giờ.');
    }
  }

  /// "Sửa bài" / "Sửa & gửi lại" on the member's own post. Returns the saved
  /// post (its `status` says whether it went back to review).
  static Future<Post?> edit(
      BuildContext context, WidgetRef ref, Post post) async {
    // Read before awaiting: the card that asked may be gone afterwards.
    final messenger = ScaffoldMessenger.of(context);
    final feed = ref.read(feedControllerProvider.notifier);
    final updated = await Navigator.of(context)
        .push<Post>(CreatePostScreen.route(editing: post));
    if (updated == null) return null;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(updated.isPending
            ? 'Bài đã được gửi lại và đang chờ Ban quản trị duyệt'
            : 'Đã lưu thay đổi'),
      ));
    feed.postUpdated(updated);
    return updated;
  }

  /// "Xoá bài": confirms, deletes, drops it from the feed. `true` if deleted.
  static Future<bool> delete(
      BuildContext context, WidgetRef ref, Post post) async {
    final messenger = ScaffoldMessenger.of(context);
    final feed = ref.read(feedControllerProvider.notifier);
    final ok = await confirm(
      context,
      title: 'Xoá bài viết?',
      message: 'Bài và các bình luận sẽ bị xoá vĩnh viễn.',
    );
    if (!ok) return false;
    try {
      await feed.deletePost(post);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Đã xoá bài viết')));
      return true;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
      return false;
    }
  }

  /// "Nội dung của tôi › Bình luận": deletes one of the member's comments
  /// (a top-level one with its replies) after confirming. `true` if gone.
  static Future<bool> deleteComment(BuildContext context, WidgetRef ref,
      {required String postId, required String commentId}) async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(communityApiProvider);
    final feed = ref.read(feedControllerProvider.notifier);
    final ok = await confirm(
      context,
      title: 'Xoá bình luận?',
      message: 'Bình luận và các phản hồi của nó sẽ bị xoá vĩnh viễn.',
    );
    if (!ok) return false;
    try {
      await api.deleteComment(postId, commentId);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Đã xoá bình luận')));
      // How many replies went with it is the server's business: take the
      // post's new count from it.
      try {
        feed.commentCountIs(postId, (await api.getPost(postId)).commentCount);
      } catch (_) {
        feed.commentsChanged(postId, -1);
      }
      return true;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
      return false;
    }
  }

  /// "Sửa" from the "Bình luận" tab: edits in a dialog. `true` if saved.
  static Future<bool> editCommentInDialog(
      BuildContext context, WidgetRef ref, MyComment comment) async {
    final messenger = ScaffoldMessenger.of(context);
    final api = ref.read(communityApiProvider);
    final feed = ref.read(feedControllerProvider.notifier);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => _EditCommentDialog(initial: comment.text),
    );
    if (text == null || text == comment.text) return false;
    try {
      await api.updateComment(comment.postId, comment.id, text);
      feed.commentEdited();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Đã lưu bình luận')));
      return true;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
      return false;
    }
  }

  /// "Giữ lại" / "Xoá" confirmation for destructive actions.
  static Future<bool> confirm(BuildContext context,
      {required String title, required String message}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.error,
              foregroundColor: context.colors.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _EditCommentDialog extends StatefulWidget {
  const _EditCommentDialog({required this.initial});

  final String initial;

  @override
  State<_EditCommentDialog> createState() => _EditCommentDialogState();
}

class _EditCommentDialogState extends State<_EditCommentDialog> {
  late final _input = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _save() {
    final text = _input.text.trim();
    if (text.isNotEmpty) Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sửa bình luận'),
      content: TextField(
        controller: _input,
        autofocus: true,
        minLines: 1,
        maxLines: 5,
        maxLength: 500,
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Huỷ'),
        ),
        ValueListenableBuilder(
          valueListenable: _input,
          builder: (context, value, _) => FilledButton(
            onPressed: value.text.trim().isEmpty ? null : _save,
            child: const Text('Lưu'),
          ),
        ),
      ],
    );
  }
}
