// lib/features/community/presentation/screens/post_detail_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/backend_modules.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../video/data/video_api_service.dart';
import '../../../video/domain/entities/video_recipe.dart';
import '../../../video/presentation/widgets/video_player_view.dart';
import '../../../video/presentation/widgets/video_recipe_sheet.dart';
import '../../data/community_api_service.dart';
import '../../domain/entities/post.dart';
import '../controllers/feed_controller.dart';
import '../post_actions.dart';
import '../widgets/comment_thread.dart';
import '../widgets/linkified_text.dart';
import '../widgets/post_card.dart';
import '../widgets/post_status_banner.dart';
import '../widgets/restaurant_tag.dart';
import '../widgets/video_status_chip.dart';

/// Where the post detail opens.
enum PostDetailEntry {
  /// The card body: top of the post.
  top,

  /// "N bình luận": scrolled to the comments, keyboard down.
  comments,

  /// "Bình luận": scrolled to the comments with the composer focused.
  writeComment,
}

/// The post (inline video or photo, "Xem công thức" for an AI recipe, body
/// with tappable links, restaurant chip, actions), then "Bình luận (N)"
/// loading 10 at a time while scrolling, newest first, replies one level
/// deep. The composer is pinned at the bottom. Video and recipe posts open
/// here too; there is no separate comments or video page.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({
    super.key,
    required this.post,
    this.entry = PostDetailEntry.top,
    this.highlightCommentId,
    this.highlightParentId,
  });

  final Post post;
  final PostDetailEntry entry;

  /// "Nội dung của tôi › Bình luận": scrolls to this comment and tints it
  /// briefly. [highlightParentId] is set when it is a reply.
  final String? highlightCommentId;
  final String? highlightParentId;

  static Route<void> route(
    Post post, {
    PostDetailEntry entry = PostDetailEntry.top,
    String? highlightCommentId,
    String? highlightParentId,
  }) =>
      MaterialPageRoute<void>(
        settings: RouteSettings(name: AppRoutes.post(post.id)),
        builder: (_) => PostDetailScreen(
          post: post,
          entry: entry,
          highlightCommentId: highlightCommentId,
          highlightParentId: highlightParentId,
        ),
      );

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen>
    with CommentSectionMixin {
  late Post _post = widget.post;
  final _scroll = ScrollController();
  final _commentsHeader = GlobalKey();
  final _revealKey = GlobalKey();
  final _player = GlobalKey<VideoPlayerViewState>();

  /// The tile [_revealKey] goes on (a new reply, the highlighted comment).
  String? _revealId;
  String? _highlightId;
  Timer? _highlightTimer;

  /// Scroll to the comments again once the first page is in.
  bool _settleOnComments = false;

  VideoRecipe? _video;
  Timer? _poll;
  bool _retrying = false;

  /// The server no longer shows this post to this member (404): hidden by an
  /// admin, or deleted.
  bool _gone = false;

  bool get _open => _post.isPublished && !_gone;

  @override
  void initState() {
    super.initState();
    initComments(widget.post);
    comments.addListener(_onCommentsChanged);
    _scroll.addListener(_onScroll);
    if (widget.post.isPublished) comments.loadMore();
    if (widget.post.videoId != null) _loadVideo();
    // The list this came from may be old.
    _recheck();

    final entry = widget.entry;
    final highlight = widget.highlightCommentId;
    if (entry != PostDetailEntry.top || highlight != null) {
      _settleOnComments = highlight == null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToComments();
        if (entry == PostDetailEntry.writeComment &&
            !ref.read(sessionControllerProvider).isGuest) {
          composerKey.currentState?.focusInput();
        }
        if (highlight != null && widget.post.isPublished) {
          _reveal(highlight, widget.highlightParentId);
        }
      });
    }
  }

  @override
  void dispose() {
    comments.removeListener(_onCommentsChanged);
    comments.dispose();
    _scroll.dispose();
    _poll?.cancel();
    _highlightTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------ comments --

  bool get _nearEnd => _scroll.hasClients && _scroll.position.extentAfter < 400;

  void _maybeLoadMore() {
    if (!_open || comments.loading || comments.error != null) return;
    if (comments.hasMore && _nearEnd) comments.loadMore();
  }

  void _onScroll() => _maybeLoadMore();

  void _onCommentsChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_settleOnComments && comments.started) {
        _settleOnComments = false;
        _scrollToComments();
      }
      // A short thread doesn't fill the screen: keep paging.
      _maybeLoadMore();
    });
  }

  void _scrollToComments({bool animate = false}) {
    final target = _commentsHeader.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: animate ? const Duration(milliseconds: 250) : Duration.zero,
      curve: Curves.easeOut,
    );
  }

  void _scrollToReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _revealKey.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(target,
          alignment: 0.3, duration: const Duration(milliseconds: 250));
    });
  }

  Future<void> _reveal(String commentId, String? parentId) async {
    final found = await comments.reveal(commentId, parentId: parentId);
    if (!mounted) return;
    if (!found) {
      _scrollToComments();
      snack('Bình luận này không còn nữa.');
      return;
    }
    setState(() {
      _revealId = commentId;
      _highlightId = commentId;
    });
    _scrollToReveal();
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  /// A new top-level comment sits right under the header; a reply is
  /// scrolled to.
  void _posted(Comment comment) {
    if (comment.isReply) {
      setState(() => _revealId = comment.id);
      _scrollToReveal();
    } else {
      _scrollToComments(animate: true);
    }
    _recheck();
  }

  @override
  void onCommentCountChanged(int delta) {
    if (!mounted) return;
    setState(() => _post = _post.copyWith(
        commentCount: (_post.commentCount + delta).clamp(0, 1 << 30)));
  }

  Future<void> _writeComment() async {
    _scrollToComments(animate: true);
    await composerKey.currentState?.focusInput();
  }

  // --------------------------------------------------------------- post --

  /// An admin can hide the post while it is open, and the BE still takes likes
  /// and comments on it, so the status is read again on opening and after each
  /// of them. Only the real BE changes behind the app's back. A failed read
  /// changes nothing: what is on screen stays.
  Future<void> _recheck() async {
    if (!BackendModules.isReal(BackendModule.community)) return;
    final feed = ref.read(feedControllerProvider.notifier);
    try {
      final fresh =
          (await ref.read(communityApiProvider).getPost(_post.id)).toEntity();
      if (!mounted || fresh.status == _post.status) return;
      setState(() {
        _gone = false;
        _post = fresh.copyWith(videoStatus: _post.videoStatus);
      });
      feed.postUpdated(fresh);
      if (fresh.isPublished && !comments.started) comments.loadMore();
    } on ApiException catch (e) {
      if (e.statusCode != 404 || !mounted || _gone) return;
      setState(() => _gone = true);
      feed.postGone(_post.id);
      snack(_goneMessage);
    } catch (_) {
      // A body of the wrong shape: same as a failed read.
    }
  }

  static const _goneMessage = 'Bài viết này không còn hiển thị.';

  /// Why a post that isn't open takes no comments.
  String get _closedMessage {
    if (_gone) return _goneMessage;
    return switch (_post.status) {
      PostStatus.hidden => 'Bài đang bị ẩn nên không nhận bình luận.',
      PostStatus.unknown =>
        'Chưa rõ trạng thái của bài nên chưa nhận bình luận.',
      _ => 'Bài chưa hiển thị trên bảng tin nên chưa nhận bình luận.',
    };
  }

  Future<void> _like() async {
    final before = _post;
    setState(() => _post = before.toggledLike());
    final result = await PostActions.toggleLike(context, ref, before);
    if (result == null && mounted) setState(() => _post = before);
    if (mounted) await _recheck();
  }

  Future<void> _save() async {
    final before = _post;
    setState(() => _post = before.toggledSave());
    final result = await PostActions.toggleSave(context, ref, before);
    if (result == null && mounted) setState(() => _post = before);
  }

  Future<void> _edit() async {
    final updated = await PostActions.edit(context, ref, _post);
    if (updated != null && mounted) setState(() => _post = updated);
  }

  /// An admin's decision of the demo: an approved post opens its comments.
  void _decided(Post decided) {
    if (!mounted) return;
    setState(() => _post = decided);
    if (decided.isPublished && !comments.started) comments.loadMore();
  }

  // -------------------------------------------------------------- video --

  /// Follows the AI pipeline every 3 s while it runs, so the chip and
  /// "Xem công thức" appear without leaving the screen.
  Future<void> _loadVideo() async {
    final id = _post.videoId;
    if (id == null) return;
    try {
      final video = (await ref.read(videoApiProvider).getVideo(id)).toEntity();
      if (!mounted) return;
      setState(() {
        _video = video;
        _post = _post.copyWith(videoStatus: video.status);
      });
      ref
          .read(feedControllerProvider.notifier)
          .videoStatusChanged(video.id, video.status);
      _poll?.cancel();
      if (video.status.isProcessing) {
        _poll = Timer(const Duration(seconds: 3), _loadVideo);
      }
    } catch (_) {
      // The chip from the post stays; the player falls back to the cover.
    }
  }

  Future<void> _retryExtraction() async {
    final id = _post.videoId;
    if (id == null) return;
    setState(() => _retrying = true);
    final ok = await retryVideoExtraction(context, ref, id);
    if (ok) await _loadVideo();
    if (mounted) setState(() => _retrying = false);
  }

  void _openRecipe() {
    final id = _post.videoId;
    if (id == null) return;
    showVideoRecipeSheet(
      context,
      videoId: id,
      title: _post.title,
      onSeek: (second) =>
          _player.currentState?.seekTo(Duration(seconds: second)),
    );
  }

  // -------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    // Prefer the feed's copy when it changes elsewhere (e.g. like from the list).
    final fromFeed = ref.watch(
      feedControllerProvider
          .select((s) => s.hasValue ? s.requireValue.byId(_post.id) : null),
    );
    final post = fromFeed == null || _gone
        ? _post
        : fromFeed.copyWith(videoStatus: _post.videoStatus);
    final open = post.isPublished && !_gone;
    final me = ref.watch(
        sessionControllerProvider.select((s) => s.isGuest ? null : s.userId));
    final own = me != null && me == post.author.id;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(post.type.label),
        actions: [
          if (!own && !_gone)
            IconButton(
              tooltip: 'Báo cáo',
              onPressed: () => PostActions.report(context, ref, post),
              icon: const Icon(Icons.flag_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(child: _postBody(context, post, own, open)),
                SliverToBoxAdapter(
                  child: ListenableBuilder(
                    listenable: comments,
                    builder: (context, _) => Padding(
                      key: _commentsHeader,
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Text(
                        'Bình luận (${open ? comments.total : 0})',
                        style: context.textStyles.titleMedium,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      16, 0, 8, 24 + (open ? 0 : bottomInset)),
                  sliver: SliverToBoxAdapter(
                    child: open
                        ? CommentThreadList(
                            controller: comments,
                            currentUserId: me,
                            highlightId: _highlightId,
                            keyFor: (id) => id == _revealId ? _revealKey : null,
                            onReply: replyTo,
                            onEdit: editComment,
                            onDelete: deleteComment,
                            onMoreReplies: loadReplies,
                          )
                        : Text(
                            _closedMessage,
                            style: context.textStyles.bodyMedium
                                ?.copyWith(color: context.vl.muted),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (open) ...[
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: CommentComposer(
                key: composerKey,
                controller: comments,
                onPosted: _posted,
                onFailed: _recheck,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _postBody(BuildContext context, Post post, bool own, bool open) {
    final restaurant = post.restaurant;
    final image = post.imageSrc;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PostAuthorRow(
          post: post,
          onEdited: (updated) {
            if (mounted) setState(() => _post = updated);
          },
          onDeleted: () {
            if (mounted) Navigator.of(context).maybePop();
          },
        ),
        if (own && !post.isPublished)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: PostStatusBanner(
              post: post,
              onResubmit: BackendModules.postEdit ? _edit : null,
              onDecided: _decided,
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(post.title,
              style: context.textStyles.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
        ),
        if (post.hasVideo)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: VideoPlayerView(
              key: _player,
              url: post.mediaUrl ?? _video?.videoUrl,
              coverSeed: post.coverSeed,
            ),
          )
        else if (post.hasCover)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: FoodCover(
              seed: post.coverSeed,
              imageUrl: image,
              aspectRatio: image != null ? 4 / 3 : 16 / 9,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        if (post.videoId != null)
          _AiRecipeRow(
            status: post.videoStatus,
            own: own,
            retrying: _retrying,
            onOpen: _openRecipe,
            onRetry: _retryExtraction,
          ),
        if (post.body.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: LinkifiedText(post.body,
                style: context.textStyles.bodyLarge?.copyWith(height: 1.55)),
          ),
        if (post.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in post.tags)
                  VLTag.neutral(context, dietTagLabel(t))
              ],
            ),
          ),
        if (restaurant != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: RestaurantTagChip(restaurant: restaurant),
            ),
          ),
        const SizedBox(height: 6),
        PostActionsBar(
          post: post,
          onLike: _like,
          onComment: _writeComment,
          onOpenComments: () => _scrollToComments(animate: true),
          onSave: _save,
          enabled: open,
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// Under the video: the AI chip, "Xem công thức" when the recipe is ready,
/// "Thử trích xuất lại" for the author when it failed.
class _AiRecipeRow extends StatelessWidget {
  const _AiRecipeRow({
    required this.status,
    required this.own,
    required this.retrying,
    required this.onOpen,
    required this.onRetry,
  });

  final VideoAiStatus? status;
  final bool own;
  final bool retrying;
  final VoidCallback onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = status;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (s == VideoAiStatus.ready)
            FilledButton.tonalIcon(
              onPressed: onOpen,
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Xem công thức'),
            ),
          if (s != null) VideoStatusChip(status: s),
          if (s == VideoAiStatus.failed && own)
            TextButton.icon(
              onPressed: retrying ? null : onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(retrying ? 'Đang gửi lại…' : 'Thử trích xuất lại'),
            ),
        ],
      ),
    );
  }
}
