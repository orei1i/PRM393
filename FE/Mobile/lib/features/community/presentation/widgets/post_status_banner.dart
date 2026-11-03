// lib/features/community/presentation/widgets/post_status_banner.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/post.dart';
import '../post_actions.dart';

/// Shown to the author above a post that is not on the feed: waiting for the
/// admins ("Chờ duyệt"), rejected with the admin's reason, hidden by an admin
/// ("Đã ẩn") or in a state this app doesn't know. While the community
/// module is mock there is no web console to decide, so a waiting post offers
/// "Duyệt thử" / "Từ chối thử" to show the rest of the flow.
class PostStatusBanner extends ConsumerStatefulWidget {
  const PostStatusBanner({
    super.key,
    required this.post,
    this.onResubmit,
    this.onDecided,
    this.showDemoActions = true,
  });

  final Post post;

  /// "Sửa & gửi lại" on a rejected post; hidden when `null`.
  final VoidCallback? onResubmit;

  /// The post after "Duyệt thử" / "Từ chối thử".
  final ValueChanged<Post>? onDecided;
  final bool showDemoActions;

  @override
  ConsumerState<PostStatusBanner> createState() => _PostStatusBannerState();
}

class _PostStatusBannerState extends ConsumerState<PostStatusBanner> {
  bool _deciding = false;

  Future<void> _decide({required bool approve}) async {
    setState(() => _deciding = true);
    final decided = await PostActions.demoDecide(context, ref, widget.post,
        approve: approve);
    if (mounted) setState(() => _deciding = false);
    if (decided != null) widget.onDecided?.call(decided);
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    if (post.isPublished) return const SizedBox.shrink();
    final vl = context.vl;
    final rejected = post.isRejected;
    // Decided by an admin: the caution look, unlike a post that still waits.
    final caution = rejected || post.isHidden;
    final fg =
        caution ? vl.onCautionContainer : context.colors.onSecondaryContainer;
    final reason = post.rejectionReason?.trim();
    final onResubmit = widget.onResubmit;
    final demo = widget.showDemoActions &&
        post.isPending &&
        BackendModules.isMock(BackendModule.community);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color:
            caution ? vl.cautionContainer : context.colors.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
        border: caution ? Border.all(color: vl.cautionBorder) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                switch (post.status) {
                  PostStatus.rejected => Icons.block_rounded,
                  PostStatus.hidden => Icons.visibility_off_outlined,
                  PostStatus.unknown => Icons.help_outline_rounded,
                  _ => Icons.hourglass_top_rounded,
                },
                size: 20,
                color: fg,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  switch (post.status) {
                    PostStatus.rejected =>
                      'Bị từ chối: ${reason == null || reason.isEmpty ? 'Ban quản trị chưa ghi lý do.' : reason}',
                    PostStatus.hidden =>
                      'Đã ẩn: Ban quản trị đã ẩn bài này nên bài không hiển thị trên bảng tin.',
                    PostStatus.unknown =>
                      'Chưa rõ trạng thái: bài có thể chưa hiển thị trên bảng tin. Thử tải lại sau.',
                    _ =>
                      'Chờ duyệt: bài sẽ hiển thị trên bảng tin sau khi Ban quản trị duyệt.',
                  },
                  style: context.textStyles.bodyMedium?.copyWith(color: fg),
                ),
              ),
            ],
          ),
          if (rejected && onResubmit != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onResubmit,
                style: TextButton.styleFrom(foregroundColor: fg),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Sửa & gửi lại'),
              ),
            ),
          if (demo) ...[
            const SizedBox(height: 8),
            Text(
              'Bản demo chưa có Ban quản trị, bạn có thể thử quyết định thay:',
              style: context.textStyles.bodySmall?.copyWith(color: fg),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _deciding ? null : () => _decide(approve: true),
                  style: TextButton.styleFrom(foregroundColor: fg),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Duyệt thử'),
                ),
                TextButton.icon(
                  onPressed: _deciding ? null : () => _decide(approve: false),
                  style: TextButton.styleFrom(foregroundColor: fg),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Từ chối thử'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
