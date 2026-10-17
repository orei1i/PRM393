// lib/features/community/presentation/screens/create_post_screen.dart
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/food_cover.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../profile/presentation/screens/my_posts_screen.dart';
import '../../data/community_api_service.dart';
import '../../data/media_api_service.dart';
import '../../data/media_picker.dart';
import '../../data/models/post_model.dart';
import '../../domain/entities/post.dart';
import '../controllers/feed_controller.dart';
import '../widgets/post_status_banner.dart';
import '../widgets/restaurant_tag.dart';

enum _UploadPhase { idle, invalid, uploading, done, failed }

/// "Tạo bài viết", Facebook-like: ✕ · title · "Đăng"; the author row, the
/// "Công thức" / "Hỏi đáp" choice, title and content (links stay in the
/// text), then the attachment, restaurant and tags; "Thêm vào bài viết" at
/// the bottom adds a photo or video from the device, a restaurant, tags.
/// One attachment per post. With [editing] it edits the member's own post
/// ("Sửa bài viết" · "Lưu"); the attachment can't change then.
///
/// Pops the saved [Post]. A new post that the AI pre-screen holds for review
/// pops `null` after its own snackbar: the feed has nothing to show yet.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key, this.editing});

  final Post? editing;

  static Route<Post> route({Post? editing}) => MaterialPageRoute<Post>(
        fullscreenDialog: true,
        builder: (_) => CreatePostScreen(editing: editing),
      );

  static const tagOptions = [
    'quick',
    'high_protein',
    'high_fiber',
    'low_sodium',
    'whole_food',
    'seasonal',
    'gluten_free'
  ];

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  PostType _type = PostType.recipe;
  final Set<String> _tags = {};
  TaggedRestaurant? _restaurant;
  bool _submitting = false;

  PickedMedia? _media;
  _UploadPhase _phase = _UploadPhase.idle;
  double _progress = 0;
  String? _uploadError;
  String? _uploadedUrl;

  /// The running upload; replaced (so late callbacks are ignored) on cancel.
  CancelToken? _upload;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    if (editing != null) {
      _type = editing.type;
      _title.text = editing.title;
      _body.text = editing.body;
      _tags.addAll(editing.tags);
      _restaurant = editing.restaurant;
    }
  }

  @override
  void dispose() {
    _upload?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _uploading => _phase == _UploadPhase.uploading;

  /// "Đăng" waits for the attachment's upload (and is off after a failed
  /// one until it is retried or removed).
  bool get _canSubmit {
    if (_submitting) return false;
    if (_isEditing || _media == null) return true;
    return _phase == _UploadPhase.done && _uploadedUrl != null;
  }

  bool get _hasVideo => _media?.isVideo ?? (widget.editing?.hasVideo ?? false);

  bool get _dirty =>
      !_isEditing &&
      (_title.text.trim().isNotEmpty ||
          _body.text.trim().isNotEmpty ||
          _media != null ||
          _restaurant != null ||
          _tags.isNotEmpty);

  // ------------------------------------------------------------- upload --

  Future<void> _pickMedia() async {
    final picked = await ref.read(mediaPickerProvider).pick(context);
    if (picked == null || !mounted) return;
    _upload?.cancel();
    _upload = null;
    final invalid = MediaUploadRules.validate(picked);
    setState(() {
      _media = picked;
      _uploadedUrl = null;
      _progress = 0;
      _uploadError = invalid;
      _phase = invalid == null ? _UploadPhase.idle : _UploadPhase.invalid;
    });
    if (invalid == null) _startUpload();
  }

  Future<void> _startUpload() async {
    final media = _media;
    if (media == null) return;
    final token = _upload = CancelToken();
    setState(() {
      _phase = _UploadPhase.uploading;
      _progress = 0;
      _uploadError = null;
      _uploadedUrl = null;
    });
    void onProgress(double p) {
      if (mounted && identical(_upload, token)) setState(() => _progress = p);
    }

    try {
      final api = ref.read(mediaApiProvider);
      final url = media.isVideo
          ? (await api.uploadVideo(media,
                  cancelToken: token, onProgress: onProgress))
              .mediaUrl
          : (await api.uploadImage(media,
                  cancelToken: token, onProgress: onProgress))
              .mediaUrl;
      if (!mounted || !identical(_upload, token)) return;
      setState(() {
        _phase = _UploadPhase.done;
        _progress = 1;
        _uploadedUrl = url;
      });
    } catch (e) {
      // Cancelled (or superseded by another file): nothing to report.
      if (!mounted || !identical(_upload, token)) return;
      if (e is ApiException && e.code == 'cancelled') return _removeMedia();
      setState(() {
        _phase = _UploadPhase.failed;
        _uploadError = describeError(e);
      });
    }
  }

  void _cancelUpload() {
    _upload?.cancel();
    _removeMedia();
  }

  void _removeMedia() => setState(() {
        _upload?.cancel();
        _upload = null;
        _media = null;
        _phase = _UploadPhase.idle;
        _progress = 0;
        _uploadError = null;
        _uploadedUrl = null;
      });

  // ------------------------------------------------- restaurant & tags --

  Future<void> _pickRestaurant() async {
    final picked = await pickTaggedRestaurant(context);
    if (picked != null && mounted) setState(() => _restaurant = picked);
  }

  Future<void> _pickTags() async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      builder: (_) => _TagsSheet(initial: _tags),
    );
    if (picked != null && mounted) {
      setState(() => _tags
        ..clear()
        ..addAll(picked));
    }
  }

  // ------------------------------------------------------------- submit --

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final api = ref.read(communityApiProvider);
    final editing = widget.editing;
    final tags = [
      for (final t in CreatePostScreen.tagOptions)
        if (_tags.contains(t)) t
    ];
    try {
      if (editing != null) {
        final dto = await api.updatePost(
          editing.id,
          UpdatePostRequestDto(
            title: _title.text.trim(),
            body: _body.text.trim(),
            tags: tags,
            mediaType: editing.mediaType,
            mediaUrl: editing.mediaUrl,
            restaurant: _restaurant,
          ),
        );
        if (mounted) Navigator.of(context).pop(dto.toEntity());
        return;
      }
      final media = _media;
      final dto = await api.createPost(
        CreatePostRequestDto(
          type: _type,
          title: _title.text.trim(),
          body: _body.text.trim(),
          tags: tags,
          mediaType: media == null
              ? PostMediaType.text
              : (media.isVideo ? PostMediaType.video : PostMediaType.image),
          mediaUrl: media == null ? null : _uploadedUrl,
          restaurant: _restaurant,
        ),
      );
      if (!mounted) return;
      final post = dto.toEntity();
      if (post.isPublished) {
        Navigator.of(context).pop(post);
      } else {
        _heldForReview();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  /// Flagged by the AI pre-screen: not on the feed until an admin approves.
  void _heldForReview() {
    ref.read(communityRevisionProvider.notifier).bump();
    final navigator = Navigator.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        persist: MediaQuery.accessibleNavigationOf(context),
        content: const Text(
            'Bài đã gửi và đang chờ Ban quản trị duyệt — chưa hiển thị trên bảng tin.'),
        action: SnackBarAction(
          label: 'Xem',
          onPressed: () => navigator
              .push(MyPostsScreen.route(initialStatus: PostStatus.pending)),
        ),
      ));
    navigator.pop();
  }

  /// ✕ or back with something written: "Bỏ bài viết?".
  Future<void> _close() async {
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bỏ bài viết?'),
        content: const Text('Nội dung bạn vừa soạn sẽ không được lưu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Tiếp tục viết'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Bỏ'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _upload?.cancel();
      Navigator.of(context).pop();
    }
  }

  // --------------------------------------------------------- validation --

  String? _validateTitle(String? v) {
    final text = v?.trim() ?? '';
    if (text.length < 8) return 'Tiêu đề cần ít nhất 8 ký tự.';
    if (text.length > 120) return 'Tiêu đề tối đa 120 ký tự.';
    return null;
  }

  String? _validateBody(String? v) {
    final text = v?.trim() ?? '';
    // A video speaks for itself.
    if (_hasVideo) return null;
    if (text.length < 20) {
      return 'Nội dung cần ít nhất 20 ký tự để cộng đồng dễ hiểu.';
    }
    return null;
  }

  // -------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing;
    final name =
        ref.watch(sessionControllerProvider.select((s) => s.displayName)) ??
            'Bạn';
    final restaurant = _restaurant;
    final media = _media;
    return PopScope<Object?>(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Đóng',
            onPressed: _close,
            icon: const Icon(Icons.close_rounded),
          ),
          title: Text(_isEditing ? 'Sửa bài viết' : 'Tạo bài viết'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _canSubmit ? _submit : null,
                style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
                child: Text(_isEditing
                    ? (_submitting ? 'Đang lưu…' : 'Lưu')
                    : (_submitting ? 'Đang đăng…' : 'Đăng')),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Form(
                key: _form,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (editing != null && !editing.isPublished) ...[
                      PostStatusBanner(post: editing),
                      if (editing.isRejected)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Sửa nội dung rồi bấm Lưu để gửi Ban quản trị duyệt lại.',
                            style: context.textStyles.bodySmall
                                ?.copyWith(color: context.vl.muted),
                          ),
                        ),
                      const SizedBox(height: 16),
                    ],
                    Row(
                      children: [
                        UserAvatar(name: name, size: 40),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: context.textStyles.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                              Text('Công khai · Cộng đồng VeganLife',
                                  style: context.textStyles.bodySmall
                                      ?.copyWith(color: context.vl.muted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SegmentedButton<PostType>(
                      segments: const [
                        ButtonSegment(
                            value: PostType.recipe,
                            icon: Icon(Icons.restaurant_menu_rounded),
                            label: Text('Công thức')),
                        ButtonSegment(
                            value: PostType.discussion,
                            icon: Icon(Icons.forum_outlined),
                            label: Text('Hỏi đáp')),
                      ],
                      selected: {_type},
                      // The category can't change once posted.
                      onSelectionChanged: _isEditing
                          ? null
                          : (s) => setState(() => _type = s.first),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _title,
                      maxLength: 120,
                      textInputAction: TextInputAction.next,
                      validator: _validateTitle,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Tiêu đề',
                        hintText: _type == PostType.recipe
                            ? 'VD: Bún riêu chay cà chua đậu hũ'
                            : 'VD: Mới ăn chay nên bổ sung B12 thế nào?',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _body,
                      minLines: 5,
                      maxLines: 14,
                      maxLength: 3000,
                      validator: _validateBody,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Nội dung',
                        alignLabelWithHint: true,
                        hintText: _type == PostType.recipe
                            ? 'Nguyên liệu, cách làm… Có link video thì dán luôn vào đây'
                            : 'Bạn muốn hỏi gì về ăn chay?',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (media != null) ...[
                      const SizedBox(height: 8),
                      _AttachmentCard(
                        media: media,
                        phase: _phase,
                        progress: _progress,
                        error: _uploadError,
                        onCancel: _cancelUpload,
                        onRetry: _startUpload,
                        onReplace: _pickMedia,
                        onRemove: _removeMedia,
                      ),
                    ] else if (editing != null &&
                        editing.mediaType != PostMediaType.text) ...[
                      const SizedBox(height: 8),
                      _PostedMediaCard(post: editing),
                    ],
                    if (_type == PostType.recipe &&
                        _hasVideo &&
                        !_isEditing) ...[
                      const SizedBox(height: 12),
                      VLCard(
                        color: context.vl.aiContainer,
                        borderColor: context.vl.aiBorder,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.auto_awesome, color: context.vl.ai),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'AI sẽ nghe lời thoại trong video, tách nguyên liệu, định lượng và từng bước kèm mốc thời gian. '
                                'Thường mất 1–3 phút; bạn có thể đóng app trong lúc chờ.',
                                style: context.textStyles.bodyMedium
                                    ?.copyWith(color: context.vl.onAiContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (restaurant != null || _tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (restaurant != null)
                            RestaurantTagChip(
                              restaurant: restaurant,
                              onTap: _pickRestaurant,
                              onRemove: () =>
                                  setState(() => _restaurant = null),
                            ),
                          for (final tag in CreatePostScreen.tagOptions)
                            if (_tags.contains(tag))
                              InputChip(
                                label: Text(dietTagLabel(tag)),
                                onDeleted: () =>
                                    setState(() => _tags.remove(tag)),
                                deleteButtonTooltipMessage:
                                    'Bỏ thẻ ${dietTagLabel(tag)}',
                              ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      'Bài viết về sức khoẻ nên ghi nguồn. Bài sai lệch hoặc quảng cáo sẽ bị AI gắn cờ và Ban quản trị xem xét.',
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: context.vl.muted),
                    ),
                  ],
                ),
              ),
            ),
            _AddToPostBar(
              onMedia: _isEditing || _uploading ? null : _pickMedia,
              mediaTooltip: _isEditing
                  ? 'Không đổi được ảnh/video khi sửa bài'
                  : 'Thêm ảnh hoặc video',
              onRestaurant: _pickRestaurant,
              onTags: _pickTags,
              hasMedia: media != null,
              hasRestaurant: restaurant != null,
              tagCount: _tags.length,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Thêm vào bài viết": Ảnh/Video · Gắn quán · Gắn thẻ. Sits above the
/// keyboard.
class _AddToPostBar extends StatelessWidget {
  const _AddToPostBar({
    required this.onMedia,
    required this.mediaTooltip,
    required this.onRestaurant,
    required this.onTags,
    required this.hasMedia,
    required this.hasRestaurant,
    required this.tagCount,
  });

  final VoidCallback? onMedia;
  final String mediaTooltip;
  final VoidCallback onRestaurant;
  final VoidCallback onTags;
  final bool hasMedia;
  final bool hasRestaurant;
  final int tagCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.vl.border))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('Thêm vào bài viết',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textStyles.titleSmall),
                ),
                _BarButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Ảnh/Video',
                  tooltip: mediaTooltip,
                  color: const Color(0xFF16A34A),
                  active: hasMedia,
                  onTap: onMedia,
                ),
                _BarButton(
                  icon: Icons.storefront_outlined,
                  label: 'Gắn quán',
                  tooltip: 'Gắn quán',
                  color: const Color(0xFFDC2626),
                  active: hasRestaurant,
                  onTap: onRestaurant,
                ),
                _BarButton(
                  icon: Icons.sell_outlined,
                  label: tagCount > 0 ? 'Gắn thẻ ($tagCount)' : 'Gắn thẻ',
                  tooltip: 'Gắn thẻ',
                  color: const Color(0xFF2563EB),
                  active: tagCount > 0,
                  onTap: onTags,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final Color color;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(active ? _filled(icon) : icon, color: color),
                  const SizedBox(height: 2),
                  Text(label,
                      maxLines: 1,
                      style: context.textStyles.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static IconData _filled(IconData icon) => switch (icon) {
        Icons.photo_library_outlined => Icons.photo_library_rounded,
        Icons.storefront_outlined => Icons.storefront_rounded,
        Icons.sell_outlined => Icons.sell_rounded,
        _ => icon,
      };
}

/// The picked photo or video and where its upload stands: progress with
/// "Huỷ tải lên", "Đã tải lên", or the error with "Thử lại"; "Đổi" picks
/// another file, ✕ removes it.
class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({
    required this.media,
    required this.phase,
    required this.progress,
    required this.error,
    required this.onCancel,
    required this.onRetry,
    required this.onReplace,
    required this.onRemove,
  });

  final PickedMedia media;
  final _UploadPhase phase;
  final double progress;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final failed =
        phase == _UploadPhase.failed || phase == _UploadPhase.invalid;
    return VLCard(
      padding: EdgeInsets.zero,
      borderColor: failed ? context.colors.error : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              _Preview(media: media),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton.filledTonal(
                  tooltip: 'Bỏ tệp đính kèm',
                  onPressed:
                      phase == _UploadPhase.uploading ? onCancel : onRemove,
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                        media.isVideo
                            ? Icons.movie_outlined
                            : Icons.image_outlined,
                        size: 20,
                        color: context.colors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${media.name} · ${media.summary}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: vl.muted)),
                    ),
                    if (phase == _UploadPhase.done)
                      Icon(Icons.check_circle_rounded, color: vl.success),
                  ],
                ),
                const SizedBox(height: 6),
                switch (phase) {
                  _UploadPhase.uploading || _UploadPhase.idle => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(999),
                          semanticsLabel: 'Tiến độ tải lên',
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Đang tải lên ${formatPercent(progress)}',
                                style: context.textStyles.bodyMedium,
                              ),
                            ),
                            TextButton(
                                onPressed: onCancel,
                                child: const Text('Huỷ tải lên')),
                          ],
                        ),
                      ],
                    ),
                  _UploadPhase.done => Row(
                      children: [
                        Expanded(
                          child: Text('Đã tải lên',
                              style: context.textStyles.bodyMedium
                                  ?.copyWith(color: vl.onSuccessContainer)),
                        ),
                        TextButton(
                            onPressed: onReplace, child: const Text('Đổi')),
                      ],
                    ),
                  _UploadPhase.failed || _UploadPhase.invalid => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(error ?? 'Chưa tải lên được tệp.',
                            style: context.textStyles.bodyMedium
                                ?.copyWith(color: context.colors.error)),
                        Wrap(
                          spacing: 4,
                          children: [
                            if (phase == _UploadPhase.failed)
                              TextButton.icon(
                                onPressed: onRetry,
                                icon:
                                    const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text('Thử lại'),
                              ),
                            TextButton(
                                onPressed: onReplace, child: const Text('Đổi')),
                          ],
                        ),
                      ],
                    ),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The local photo (or an illustration for the mock samples); a dark frame
/// with a play mark for a video.
class _Preview extends StatelessWidget {
  const _Preview({required this.media});

  final PickedMedia media;

  @override
  Widget build(BuildContext context) {
    if (media.isVideo) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ColoredBox(
          color: Colors.black,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_circle_fill_rounded,
                    size: 56, color: Colors.white70),
                if (media.durationSeconds > 0)
                  Text(formatDuration(media.durationSeconds),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
    }
    final path = media.path;
    if (path != null) {
      return AspectRatio(
        aspectRatio: 4 / 3,
        child: kIsWeb
            ? Image.network(path, fit: BoxFit.cover)
            : Image.file(File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    FoodCover(seed: media.name, aspectRatio: 4 / 3)),
      );
    }
    return FoodCover(seed: media.name, aspectRatio: 4 / 3);
  }
}

/// Edit mode: the attachment can't be swapped on an existing post.
class _PostedMediaCard extends StatelessWidget {
  const _PostedMediaCard({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final seconds = post.videoDurationSeconds;
    final video = post.hasVideo;
    return VLCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(video ? Icons.videocam_outlined : Icons.image_outlined,
              color: context.colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  !video
                      ? 'Ảnh đã đăng'
                      : seconds == null || seconds <= 0
                          ? 'Video đã đăng'
                          : 'Video đã đăng · ${formatDuration(seconds)}',
                  style: context.textStyles.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Không đổi được ảnh/video khi sửa bài. Muốn đổi, hãy xoá bài và đăng lại.',
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.vl.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Gắn thẻ": the diet tags; pops the chosen set on "Xong".
class _TagsSheet extends StatefulWidget {
  const _TagsSheet({required this.initial});

  final Set<String> initial;

  @override
  State<_TagsSheet> createState() => _TagsSheetState();
}

class _TagsSheetState extends State<_TagsSheet> {
  late final Set<String> _selected = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Gắn thẻ', style: context.textStyles.titleLarge),
            const SizedBox(height: 4),
            Text('Giúp mọi người tìm thấy bài của bạn.',
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in CreatePostScreen.tagOptions)
                  FilterChip(
                    label: Text(dietTagLabel(tag)),
                    selected: _selected.contains(tag),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _selected.add(tag);
                      } else {
                        _selected.remove(tag);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_selected),
              child: const Text('Xong'),
            ),
          ],
        ),
      ),
    );
  }
}
