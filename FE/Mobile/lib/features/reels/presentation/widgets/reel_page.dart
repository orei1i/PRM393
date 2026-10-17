// lib/features/reels/presentation/widgets/reel_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../community/domain/entities/post.dart';
import '../../../community/presentation/post_actions.dart';
import '../../../community/presentation/widgets/comments_sheet.dart';
import '../../../video/presentation/widgets/video_recipe_sheet.dart';
import '../../domain/reel.dart';
import '../controllers/reels_controller.dart';

/// One full-screen reel. Only the [active] page holds a playing video: it
/// starts when the page becomes active, pauses when the user swipes on,
/// opens the comments or recipe sheet, or leaves the app, and the player is
/// disposed with the page. A clip that fails to load keeps its poster with
/// "Thử lại". Actions: Thích · Bình luận (sheet) · Lưu, and "Xem công
/// thức" (sheet) when the AI recipe is ready.
class ReelPage extends ConsumerStatefulWidget {
  const ReelPage({
    super.key,
    required this.reel,
    required this.active,
    required this.muted,
    required this.onChanged,
  });

  final Reel reel;
  final bool active;
  final bool muted;

  /// The post after a like / save / comment, for the screen's list.
  final ValueChanged<Post> onChanged;

  @override
  ConsumerState<ReelPage> createState() => _ReelPageState();
}

class _ReelPageState extends ConsumerState<ReelPage>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _failed = false;

  /// Paused with a tap: stays paused until the next tap.
  bool _pausedByUser = false;

  Post get _post => widget.reel.post;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.active && _controller == null) _start();
      });
    }
  }

  @override
  void didUpdateWidget(ReelPage old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      if (widget.active) {
        _pausedByUser = false;
        _controller == null ? _start() : _resume();
      } else {
        _controller?.pause();
      }
    }
    if (widget.muted != old.muted) {
      _controller?.setVolume(widget.muted ? 0 : 1);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else {
      _controller?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final url = widget.reel.videoUrl;
    if (url == null) {
      setState(() => _failed = true);
      return;
    }
    final VideoPlayerController controller;
    try {
      controller = ref.read(reelVideoFactoryProvider)(url);
    } catch (_) {
      setState(() => _failed = true);
      return;
    }
    setState(() {
      _controller = controller;
      _loading = true;
      _failed = false;
    });
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(widget.muted ? 0 : 1);
    } catch (_) {
      if (mounted && _controller == controller) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
      return;
    }
    if (!mounted || _controller != controller) return;
    setState(() => _loading = false);
    _resume();
  }

  void _resume() {
    final c = _controller;
    if (!widget.active || _pausedByUser || !mounted) return;
    if (c != null && c.value.isInitialized && !c.value.isPlaying) c.play();
  }

  Future<void> _retry() async {
    final old = _controller;
    setState(() {
      _controller = null;
      _failed = false;
    });
    await old?.dispose();
    if (mounted) _start();
  }

  void _togglePlay() {
    final c = _controller;
    if (_failed) {
      _retry();
      return;
    }
    if (c == null || !c.value.isInitialized) return;
    HapticFeedback.selectionClick();
    if (c.value.isPlaying) {
      c.pause();
      setState(() => _pausedByUser = true);
    } else {
      setState(() => _pausedByUser = false);
      c.play();
    }
  }

  /// Pauses while a sheet covers the reel, then plays on.
  Future<void> _away(Future<void> Function() open) async {
    _controller?.pause();
    await open();
    if (mounted) _resume();
  }

  Future<void> _like() async {
    final updated = await PostActions.toggleLike(context, ref, _post);
    if (updated != null) widget.onChanged(updated);
  }

  Future<void> _save() async {
    final updated = await PostActions.toggleSave(context, ref, _post);
    if (updated != null) widget.onChanged(updated);
  }

  /// "Bình luận": the thread in a bottom sheet over the reel.
  Future<void> _comment() => _away(() {
        var post = _post;
        return showCommentsSheet(context, post, onCountChanged: (delta) {
          post = post.copyWith(
              commentCount: (post.commentCount + delta).clamp(0, 1 << 30));
          widget.onChanged(post);
        });
      });

  /// "Xem công thức": the AI recipe in a bottom sheet; a timestamp seeks
  /// this reel.
  void _openRecipe() {
    final videoId = _post.videoId;
    if (videoId == null) return;
    var seeked = false;
    _away(() => showVideoRecipeSheet(
          context,
          videoId: videoId,
          title: _post.title,
          onSeek: (second) {
            seeked = true;
            _controller?.seekTo(Duration(seconds: second));
          },
        )).then((_) {
      // A seek is a request to watch: play even if paused by hand.
      if (seeked && mounted) {
        setState(() => _pausedByUser = false);
        _resume();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = c != null && c.value.isInitialized && !_failed;
    final post = _post;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Poster until the first frame (and behind a failed clip).
          FoodCover(seed: post.coverSeed, imageUrl: post.imageUrl),
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: c.value.size.width,
                height: c.value.size.height,
                child: VideoPlayer(c),
              ),
            ),
          // Legibility for the white text and icons.
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0xB3000000),
                  ],
                  stops: [0, 0.18, 0.55, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Semantics(
              button: true,
              label: _pausedByUser ? 'Phát video' : 'Tạm dừng video',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _togglePlay,
              ),
            ),
          ),
          if (_loading && !_failed)
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          if (_failed) Center(child: _LoadError(onRetry: _retry)),
          if (ready && _pausedByUser)
            const IgnorePointer(
              child: Center(
                child: Icon(Icons.play_arrow_rounded,
                    size: 88, color: Colors.white70),
              ),
            ),
          Positioned(
            right: 8,
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
            child: _ActionRail(
              post: post,
              onLike: _like,
              onComment: _comment,
              onSave: _save,
            ),
          ),
          Positioned(
            left: 16,
            right: 80,
            bottom: 24 + MediaQuery.paddingOf(context).bottom,
            child: _Caption(
              reel: widget.reel,
              onOpenRecipe: widget.reel.hasRecipe ? _openRecipe : null,
            ),
          ),
          if (ready)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom,
              child: VideoProgressIndicator(
                c,
                allowScrubbing: true,
                padding: const EdgeInsets.only(top: 8),
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white, size: 32),
          const SizedBox(height: 8),
          const Text(
            'Không phát được video. Kiểm tra kết nối rồi thử lại.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size(48, 44),
            ),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }
}

class _ActionRail extends StatelessWidget {
  const _ActionRail({
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RailButton(
          icon: post.likedByMe
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          color: post.likedByMe ? const Color(0xFFFF5C7A) : Colors.white,
          label: formatInt(post.likeCount),
          tooltip: post.likedByMe ? 'Bỏ thích' : 'Thích',
          onTap: onLike,
        ),
        _RailButton(
          icon: Icons.mode_comment_outlined,
          label: formatInt(post.commentCount),
          tooltip: 'Bình luận',
          onTap: onComment,
        ),
        _RailButton(
          icon: post.savedByMe
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          label: post.savedByMe ? 'Đã lưu' : 'Lưu',
          tooltip: post.savedByMe ? 'Bỏ lưu' : 'Lưu',
          onTap: onSave,
        ),
      ],
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: tooltip,
            onPressed: onTap,
            style: IconButton.styleFrom(
              backgroundColor: Colors.black.withValues(alpha: 0.35),
              minimumSize: const Size(48, 48),
            ),
            icon: Icon(icon, color: color, size: 28),
          ),
          ExcludeSemantics(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Caption extends StatefulWidget {
  const _Caption({required this.reel, required this.onOpenRecipe});

  final Reel reel;

  /// "Xem công thức"; null when the video has no AI recipe.
  final VoidCallback? onOpenRecipe;

  @override
  State<_Caption> createState() => _CaptionState();
}

class _CaptionState extends State<_Caption> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final post = widget.reel.post;
    const white = TextStyle(
        color: Colors.white, shadows: [Shadow(blurRadius: 6)], height: 1.3);
    final seconds = widget.reel.durationSeconds;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            UserAvatar(
                name: post.author.name,
                size: 32,
                verified: post.author.isVerifiedChef),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                post.author.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    white.copyWith(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            if (seconds != null && seconds > 0) ...[
              const SizedBox(width: 8),
              Text('· ${formatDuration(seconds)}',
                  style: white.copyWith(fontSize: 13)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Text(
            post.body.isEmpty ? post.title : '${post.title}\n${post.body}',
            maxLines: _expanded ? 8 : 2,
            overflow: TextOverflow.ellipsis,
            style: white.copyWith(fontSize: 14),
          ),
        ),
        if (widget.onOpenRecipe != null) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: widget.onOpenRecipe,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size(48, 40),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('Xem công thức'),
          ),
        ],
      ],
    );
  }
}
