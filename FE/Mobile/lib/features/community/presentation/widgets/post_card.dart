// lib/features/community/presentation/widgets/post_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/post.dart';
import '../post_actions.dart';
import 'video_status_chip.dart';

const _likeRed = Color(0xFFE11D48);

/// Feed item, edge to edge like a social feed: author row → title → body
/// (4 lines, "Xem thêm") → full-bleed media → tags → stats → Thích /
/// Bình luận / Lưu. Lists separate items with [PostListGap]. Likes, saves and
/// comments only work on published posts.
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
    // Photos read best tall; covers and video frames stay 16:9.
    final aspect = !isVideo && post.imageUrl != null ? 4 / 5 : 16 / 9;
    return Material(
      color: context.colors.surface,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (post.isPinned)
              Container(
                width: double.infinity,
                color: context.colors.primary.withValues(alpha: 0.07),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Icon(Icons.push_pin_rounded,
                        size: 16, color: context.colors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Ghim bởi Ban quản trị',
                        style: context.textStyles.labelMedium
                            ?.copyWith(color: context.colors.primary),
                      ),
                    ),
                  ],
                ),
              ),
            PostAuthorRow(post: post, onReport: onReport),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(post.title,
                      style: context.textStyles.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (post.body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _ExpandableBody(text: post.body),
                  ],
                ],
              ),
            ),
            if (post.hasCover)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: GestureDetector(
                  onTap: isVideo ? onOpenVideo ?? onOpen : onOpen,
                  child: FoodCover(
                    seed: post.coverSeed,
                    imageUrl: post.imageUrl,
                    aspectRatio: aspect,
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
            PostActionsBar(
              post: post,
              onLike: onLike,
              onComment: onComment,
              onSave: onSave,
              enabled: post.isPublished,
            ),
          ],
        ),
      ),
    );
  }
}

/// The 8 dp surface-tone band between two full-width posts.
class PostListGap extends StatelessWidget {
  const PostListGap({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: context.colors.surfaceContainerHigh,
        child: const SizedBox(height: 8, width: double.infinity),
      );
}

/// Body clamped to 4 lines; "Xem thêm" expands it in place.
class _ExpandableBody extends StatefulWidget {
  const _ExpandableBody({required this.text});

  final String text;

  @override
  State<_ExpandableBody> createState() => _ExpandableBodyState();
}

class _ExpandableBodyState extends State<_ExpandableBody> {
  static const _maxLines = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final style =
        context.textStyles.bodyMedium?.copyWith(color: context.vl.muted);
    if (_expanded) return Text(widget.text, style: style);
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: TextSpan(text: widget.text, style: style),
        maxLines: _maxLines,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: constraints.maxWidth);
      final overflows = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.text,
              maxLines: _maxLines,
              overflow: TextOverflow.ellipsis,
              style: style),
          if (overflows)
            InkWell(
              onTap: () => setState(() => _expanded = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('Xem thêm',
                    style: context.textStyles.labelLarge?.copyWith(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      );
    });
  }
}

enum _OwnPostAction { edit, delete }

/// Avatar, name and time. The "⋯" menu offers "Sửa bài" / "Xoá bài" on the
/// signed-in member's own post (wherever the row is shown) and "Báo cáo bài
/// viết" on everyone else's when [onReport] is set.
class PostAuthorRow extends ConsumerWidget {
  const PostAuthorRow({
    super.key,
    required this.post,
    this.onReport,
    this.onEdited,
    this.onDeleted,
  });

  final Post post;
  final VoidCallback? onReport;

  /// Own post: the saved post after "Sửa bài" (the feed is already updated).
  final ValueChanged<Post>? onEdited;

  /// Own post: after "Xoá bài" succeeded, e.g. to leave the detail screen.
  final VoidCallback? onDeleted;

  Future<void> _onOwnAction(
      BuildContext context, WidgetRef ref, _OwnPostAction action) async {
    switch (action) {
      case _OwnPostAction.edit:
        final updated = await PostActions.edit(context, ref, post);
        if (updated != null) onEdited?.call(updated);
      case _OwnPostAction.delete:
        if (await PostActions.delete(context, ref, post)) onDeleted?.call();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(
        sessionControllerProvider.select((s) => s.isGuest ? null : s.userId));
    final own = me != null && me == post.author.id;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 10),
      child: Row(
        children: [
          UserAvatar(
              name: post.author.name,
              size: 40,
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
                      Icon(Icons.verified_rounded,
                          size: 16, color: context.vl.success),
                      const SizedBox(width: 2),
                      Text('Chuyên gia',
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
          if (own)
            PopupMenuButton<_OwnPostAction>(
              tooltip: 'Tuỳ chọn',
              icon: Icon(Icons.more_horiz_rounded, color: context.vl.muted),
              onSelected: (action) => _onOwnAction(context, ref, action),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _OwnPostAction.edit,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Sửa bài'),
                  ),
                ),
                PopupMenuItem(
                  value: _OwnPostAction.delete,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline_rounded,
                        color: context.colors.error),
                    title: Text('Xoá bài',
                        style: TextStyle(color: context.colors.error)),
                  ),
                ),
              ],
            )
          else if (onReport != null)
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

/// Stats line ("❤ 214 · 27 bình luận"), a hairline, then three equal
/// buttons: Thích · Bình luận · Lưu.
class PostActionsBar extends StatelessWidget {
  const PostActionsBar({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
    required this.onSave,
    this.enabled = true,
  });

  final Post post;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onSave;

  /// `false` while the post waits for review (or was rejected).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final liked = post.likedByMe;
    final muted =
        context.textStyles.bodySmall?.copyWith(color: context.vl.muted);
    final hasStats = post.likeCount > 0 || post.commentCount > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasStats)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                if (post.likeCount > 0) ...[
                  const Icon(Icons.favorite_rounded, size: 16, color: _likeRed),
                  const SizedBox(width: 4),
                  Text(formatInt(post.likeCount), style: muted),
                ],
                const Spacer(),
                if (post.commentCount > 0)
                  InkWell(
                    onTap: enabled ? onComment : null,
                    child: Text('${formatInt(post.commentCount)} bình luận',
                        style: muted),
                  ),
              ],
            ),
          )
        else
          const SizedBox(height: 10),
        const Divider(height: 1, indent: 16, endIndent: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: liked
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  label: 'Thích',
                  tooltip: liked ? 'Bỏ thích' : 'Thích',
                  color: liked ? _likeRed : null,
                  onTap: enabled ? onLike : null,
                ),
              ),
              Expanded(
                child: _ActionButton(
                  icon: Icons.mode_comment_outlined,
                  label: 'Bình luận',
                  tooltip: 'Bình luận',
                  onTap: enabled ? onComment : null,
                ),
              ),
              Expanded(
                child: _ActionButton(
                  icon: post.savedByMe
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  label: 'Lưu',
                  tooltip: post.savedByMe ? 'Bỏ lưu' : 'Lưu',
                  color: post.savedByMe ? context.colors.primary : null,
                  onTap: enabled ? onSave : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? context.vl.muted;
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.45 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, anim) =>
                        ScaleTransition(scale: anim, child: child),
                    child: Icon(icon, key: ValueKey(icon), size: 20, color: fg),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.labelLarge
                          ?.copyWith(color: fg, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
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
              left: 12,
              top: 12,
              child: VideoStatusChip(status: post.videoStatus!)),
        if (seconds != null && seconds > 0)
          Positioned(
            right: 12,
            bottom: 12,
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
