// lib/features/community/presentation/post_actions.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/sign_in_sheet.dart';
import '../domain/entities/post.dart';
import 'controllers/feed_controller.dart';
import 'widgets/comments_sheet.dart';
import 'widgets/report_post_sheet.dart';

/// Shared like / save / comment / report handlers for the feed card and the
/// post detail screen. Each returns the post as it should now be displayed,
/// or `null` when nothing changed (guest dismissed sign-in, request failed).
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

  /// Opens the comments sheet. [onAdded] fires for each confirmed comment.
  static Future<void> openComments(BuildContext context, Post post,
      {ValueChanged<Comment>? onAdded}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CommentsSheet(post: post, onAdded: onAdded),
    );
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

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
