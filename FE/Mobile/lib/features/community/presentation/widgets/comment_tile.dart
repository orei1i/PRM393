// lib/features/community/presentation/widgets/comment_tile.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../domain/entities/post.dart';

enum _CommentAction { edit, delete }

/// Avatar, name, time ("(đã sửa)" once edited) and text. [onEdit] /
/// [onDelete] add a "⋯" menu, for the member's own comments.
class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    this.onEdit,
    this.onDelete,
  });

  final Comment comment;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    final hasMenu = !comment.pending && (onEdit != null || onDelete != null);
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
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      comment.author.name,
                      style: context.textStyles.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      comment.pending
                          ? 'Đang gửi…'
                          : relativeTime(comment.createdAt),
                      style: muted,
                    ),
                    if (comment.isEdited) Text('(đã sửa)', style: muted),
                  ],
                ),
                const SizedBox(height: 2),
                Text(comment.text, style: context.textStyles.bodyMedium),
              ],
            ),
          ),
          if (hasMenu)
            PopupMenuButton<_CommentAction>(
              tooltip: 'Tuỳ chọn bình luận',
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_horiz_rounded,
                  size: 20, color: context.vl.muted),
              onSelected: (action) => switch (action) {
                _CommentAction.edit => onEdit?.call(),
                _CommentAction.delete => onDelete?.call(),
              },
              itemBuilder: (context) => [
                if (onEdit != null)
                  const PopupMenuItem(
                    value: _CommentAction.edit,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Sửa'),
                    ),
                  ),
                if (onDelete != null)
                  PopupMenuItem(
                    value: _CommentAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline_rounded,
                          color: context.colors.error),
                      title: Text('Xoá',
                          style: TextStyle(color: context.colors.error)),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
