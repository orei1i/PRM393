// lib/features/community/presentation/widgets/post_status_banner.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/post.dart';

/// Shown to the author above a post that is not on the feed: waiting for the
/// admins ("Chờ duyệt") or rejected with the admin's reason.
class PostStatusBanner extends StatelessWidget {
  const PostStatusBanner({super.key, required this.post, this.onResubmit});

  final Post post;

  /// "Sửa & gửi lại" on a rejected post; hidden when `null`.
  final VoidCallback? onResubmit;

  @override
  Widget build(BuildContext context) {
    if (post.isPublished) return const SizedBox.shrink();
    final vl = context.vl;
    final rejected = post.isRejected;
    final fg =
        rejected ? vl.onCautionContainer : context.colors.onSecondaryContainer;
    final reason = post.rejectionReason?.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color:
            rejected ? vl.cautionContainer : context.colors.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
        border: rejected ? Border.all(color: vl.cautionBorder) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                rejected ? Icons.block_rounded : Icons.hourglass_top_rounded,
                size: 20,
                color: fg,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  rejected
                      ? 'Bị từ chối: ${reason == null || reason.isEmpty ? 'Ban quản trị chưa ghi lý do.' : reason}'
                      : 'Đang chờ Ban quản trị xem xét — bài chưa hiển thị trên bảng tin',
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
        ],
      ),
    );
  }
}
