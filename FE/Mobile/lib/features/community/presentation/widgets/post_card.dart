// lib/features/community/presentation/widgets/post_card.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/post.dart';
import 'video_status_chip.dart';

/// Feed item: author row → title/body → cover (recipe/video) → tags → actions.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onOpen,
    required this.onLike,
    required this.onComment,
    required this.onSave,
    this.onReport,
    this.onOpenVideo,
  });

  final Post post;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onSave;
  final VoidCallback? onReport;
  final VoidCallback? onOpenVideo;

  @override
  Widget build(BuildContext context) {
    final isVideo = post.type == PostType.video;
    return VLCard(
      padding: EdgeInsets.zero,
      borderColor:
          post.isPinned ? context.colors.primary.withValues(alpha: 0.35) : null,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (post.isPinned)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.push_pin_rounded,
                      size: 16, color: context.colors.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Ghim bởi Ban quản trị',
                    style: context.textStyles.labelMedium
                        ?.copyWith(color: context.colors.primary),
                  ),
                ],
              ),
            ),
          PostAuthorRow(post: post, onReport: onReport),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(post.title,
                    style: context.textStyles.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (post.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    post.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.bodyMedium
                        ?.copyWith(color: context.vl.muted),
                  ),
                ],
              ],
            ),
          ),
          if (post.hasCover)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: isVideo ? onOpenVideo : onOpen,
                child: FoodCover(
                  seed: post.coverSeed,
                  imageUrl: post.imageUrl,
                  aspectRatio: 16 / 9,
                  borderRadius: BorderRadius.circular(14),
                  child: isVideo ? _VideoOverlay(post: post) : null,
                ),
              ),
            ),
          if (post.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in post.tags)
                    VLTag.neutral(context, dietTagLabel(t))
                ],
              ),
            ),
          const SizedBox(height: 4),
          PostActionsBar(
              post: post, onLike: onLike, onComment: onComment, onSave: onSave),
        ],
      ),
    );
  }
}

class PostAuthorRow extends StatelessWidget {
  const PostAuthorRow({super.key, required this.post, this.onReport});

  final Post post;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 10),
      child: Row(
        children: [
          UserAvatar(
              name: post.author.name,
              size: 38,
              verified: post.author.isVerifiedChef),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        post.author.name,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (post.author.isVerifiedChef) ...[
                      const SizedBox(width: 4),
                      Text('· Chuyên gia',
                          style: context.textStyles.labelMedium
                              ?.copyWith(color: context.vl.success)),
                    ],
                  ],
                ),
                Text(
                  '${relativeTime(post.createdAt)} · ${post.type.label}',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.vl.muted),
                ),
              ],
            ),
          ),
          if (onReport != null)
            PopupMenuButton<String>(
              tooltip: 'Tuỳ chọn',
              icon: Icon(Icons.more_horiz_rounded, color: context.vl.muted),
              onSelected: (_) => onReport!(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'report',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.flag_outlined),
                    title: Text('Báo cáo bài viết'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class PostActionsBar extends StatelessWidget {
  const PostActionsBar({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onSave,
  });

  final Post post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final liked = post.likedByMe;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Row(
        children: [
          _CountButton(
            icon:
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: liked ? const Color(0xFFE11D48) : null,
            label: formatInt(post.likeCount),
            tooltip: liked ? 'Bỏ thích' : 'Thích',
            onTap: onLike,
          ),
          _CountButton(
            icon: Icons.mode_comment_outlined,
            label: formatInt(post.commentCount),
            tooltip: 'Bình luận',
            onTap: onComment,
          ),
          const Spacer(),
          IconButton(
            tooltip: post.savedByMe ? 'Bỏ lưu' : 'Lưu',
            onPressed: onSave,
            icon: Icon(
              post.savedByMe
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              color: post.savedByMe ? context.colors.primary : context.vl.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountButton extends StatelessWidget {
  const _CountButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Icon(icon,
                    key: ValueKey(icon),
                    size: 22,
                    color: color ?? context.vl.muted),
              ),
              const SizedBox(width: 6),
              Text(label,
                  style: context.textStyles.labelLarge
                      ?.copyWith(color: context.vl.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoOverlay extends StatelessWidget {
  const _VideoOverlay({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final seconds = post.videoDurationSeconds;
    return Stack(
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 36),
          ),
        ),
        if (post.videoStatus != null)
          Positioned(
              left: 10,
              top: 10,
              child: VideoStatusChip(status: post.videoStatus!)),
        if (seconds != null && seconds > 0)
          Positioned(
            right: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                formatDuration(seconds),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }
}
