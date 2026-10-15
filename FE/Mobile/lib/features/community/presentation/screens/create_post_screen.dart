// lib/features/community/presentation/screens/create_post_screen.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../profile/presentation/screens/my_posts_screen.dart';
import '../../data/community_api_service.dart';
import '../../data/media_api_service.dart';
import '../../data/models/post_model.dart';
import '../../data/video_picker.dart';
import '../../domain/entities/post.dart';
import '../controllers/feed_controller.dart';
import '../widgets/post_status_banner.dart';

enum _VideoSource { upload, link }

enum _UploadPhase { idle, invalid, uploading, done, failed }

/// Composer for discussion / recipe / video posts (uploaded file or link),
/// and editor for the member's own post when [editing] is set.
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

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  static const _tagOptions = [
    'quick',
    'high_protein',
    'high_fiber',
    'low_sodium',
    'whole_food',
    'seasonal',
    'gluten_free'
  ];

  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _videoUrl = TextEditingController();
  PostType _type = PostType.recipe;
  final Set<String> _tags = {};
  bool _submitting = false;

  _VideoSource _source = _VideoSource.upload;
  PickedVideo? _video;
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
    }
  }

  @override
  void dispose() {
    _upload?.cancel();
    _title.dispose();
    _body.dispose();
    _videoUrl.dispose();
    super.dispose();
  }

  /// "Đăng" waits for the upload in upload mode.
  bool get _canSubmit {
    if (_submitting) return false;
    if (_isEditing || _type != PostType.video || _source == _VideoSource.link) {
      return true;
    }
    return _phase == _UploadPhase.done && _uploadedUrl != null;
  }

  // ------------------------------------------------------------- upload --

  Future<void> _pickVideo() async {
    final picked = await ref.read(videoPickerProvider).pick(context);
    if (picked == null || !mounted) return;
    _upload?.cancel();
    _upload = null;
    final invalid = VideoUploadRules.validate(picked);
    setState(() {
      _video = picked;
      _uploadedUrl = null;
      _progress = 0;
      _uploadError = invalid;
      _phase = invalid == null ? _UploadPhase.idle : _UploadPhase.invalid;
    });
    if (invalid == null) _startUpload();
  }

  Future<void> _startUpload() async {
    final video = _video;
    if (video == null) return;
    final token = _upload = CancelToken();
    setState(() {
      _phase = _UploadPhase.uploading;
      _progress = 0;
      _uploadError = null;
      _uploadedUrl = null;
    });
    try {
      final result = await ref.read(mediaApiProvider).uploadVideo(
        video,
        cancelToken: token,
        onProgress: (p) {
          if (mounted && identical(_upload, token)) {
            setState(() => _progress = p);
          }
        },
      );
      if (!mounted || !identical(_upload, token)) return;
      setState(() {
        _phase = _UploadPhase.done;
        _progress = 1;
        _uploadedUrl = result.mediaUrl;
      });
    } catch (e) {
      // Cancelled (or superseded by another file): nothing to report.
      if (!mounted || !identical(_upload, token)) return;
      if (e is ApiException && e.code == 'cancelled') return _resetUpload();
      setState(() {
        _phase = _UploadPhase.failed;
        _uploadError = describeError(e);
      });
    }
  }

  void _cancelUpload() {
    _upload?.cancel();
    _resetUpload();
  }

  void _resetUpload() => setState(() {
        _upload = null;
        _video = null;
        _phase = _UploadPhase.idle;
        _progress = 0;
        _uploadError = null;
        _uploadedUrl = null;
      });

  // ------------------------------------------------------------- submit --

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final api = ref.read(communityApiProvider);
    final editing = widget.editing;
    try {
      if (editing != null) {
        final dto = await api.updatePost(
          editing.id,
          UpdatePostRequestDto(
            title: _title.text.trim(),
            body: _body.text.trim(),
            tags: _tags.toList(),
            mediaType: editing.mediaType,
            mediaUrl: editing.mediaUrl,
          ),
        );
        if (mounted) Navigator.of(context).pop(dto.toEntity());
        return;
      }
      final isVideo = _type == PostType.video;
      final url = !isVideo
          ? null
          : _source == _VideoSource.upload
              ? _uploadedUrl
              : _videoUrl.text.trim();
      final dto = await api.createPost(
        CreatePostRequestDto(
          type: _type,
          title: _title.text.trim(),
          body: _body.text.trim(),
          tags: _tags.toList(),
          mediaType: isVideo ? PostMediaType.video : null,
          mediaUrl: url,
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

  // --------------------------------------------------------- validation --

  String? _validateTitle(String? v) {
    final text = v?.trim() ?? '';
    if (text.length < 8) return 'Tiêu đề cần ít nhất 8 ký tự.';
    if (text.length > 120) return 'Tiêu đề tối đa 120 ký tự.';
    return null;
  }

  String? _validateUrl(String? v) {
    if (_type != PostType.video || _source != _VideoSource.link) return null;
    final uri = Uri.tryParse(v?.trim() ?? '');
    if (uri == null ||
        !(uri.isScheme('https') || uri.isScheme('http')) ||
        uri.host.isEmpty) {
      return 'Dán đường dẫn video (YouTube, TikTok, Facebook hoặc file .mp4).';
    }
    return null;
  }

  String? _validateBody(String? v) {
    final text = v?.trim() ?? '';
    if (_type == PostType.video) return null;
    if (text.length < 20) {
      return 'Nội dung cần ít nhất 20 ký tự để cộng đồng dễ hiểu.';
    }
    return null;
  }

  // -------------------------------------------------------------- build --

  @override
  Widget build(BuildContext context) {
    final editing = widget.editing;
    return Scaffold(
      appBar: AppBar(
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
      body: Form(
        key: _form,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
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
            SegmentedButton<PostType>(
              segments: const [
                ButtonSegment(
                    value: PostType.recipe,
                    icon: Icon(Icons.restaurant_menu_rounded),
                    label: Text('Công thức')),
                ButtonSegment(
                    value: PostType.video,
                    icon: Icon(Icons.videocam_outlined),
                    label: Text('Video')),
                ButtonSegment(
                    value: PostType.discussion,
                    icon: Icon(Icons.forum_outlined),
                    label: Text('Hỏi đáp')),
              ],
              selected: {_type},
              // The category can't change once posted.
              onSelectionChanged:
                  _isEditing ? null : (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _title,
              maxLength: 120,
              textInputAction: TextInputAction.next,
              validator: _validateTitle,
              decoration: InputDecoration(
                labelText: 'Tiêu đề',
                hintText: switch (_type) {
                  PostType.recipe => 'VD: Bún riêu chay cà chua đậu hũ',
                  PostType.video => 'VD: Chả lụa chay từ đậu hũ ky',
                  PostType.discussion =>
                    'VD: Mới ăn chay nên bổ sung B12 thế nào?',
                },
                border: const OutlineInputBorder(),
              ),
            ),
            if (_type == PostType.video) ...[
              const SizedBox(height: 8),
              if (editing != null)
                _PostedVideoCard(post: editing)
              else
                ..._videoInput(context),
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
            const SizedBox(height: 16),
            TextFormField(
              controller: _body,
              minLines: 5,
              maxLines: 12,
              maxLength: 3000,
              validator: _validateBody,
              decoration: InputDecoration(
                labelText: _type == PostType.video
                    ? 'Mô tả (không bắt buộc)'
                    : 'Nội dung',
                alignLabelWithHint: true,
                hintText: _type == PostType.recipe
                    ? 'Nguyên liệu: …\n1. …\n2. …'
                    : 'Chia sẻ chi tiết để mọi người dễ trả lời',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Gắn thẻ', style: context.textStyles.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tag in _tagOptions)
                  FilterChip(
                    label: Text(dietTagLabel(tag)),
                    selected: _tags.contains(tag),
                    onSelected: (on) => setState(() {
                      if (on) {
                        _tags.add(tag);
                      } else {
                        _tags.remove(tag);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'Bài viết về sức khoẻ nên ghi nguồn. Bài sai lệch hoặc quảng cáo sẽ bị AI gắn cờ và Ban quản trị xem xét.',
              style: context.textStyles.bodySmall
                  ?.copyWith(color: context.vl.muted),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _videoInput(BuildContext context) {
    return [
      SegmentedButton<_VideoSource>(
        segments: const [
          ButtonSegment(
              value: _VideoSource.upload,
              icon: Icon(Icons.upload_rounded),
              label: Text('Tải video lên')),
          ButtonSegment(
              value: _VideoSource.link,
              icon: Icon(Icons.link_rounded),
              label: Text('Dán đường dẫn')),
        ],
        selected: {_source},
        onSelectionChanged: (s) => setState(() => _source = s.first),
      ),
      const SizedBox(height: 12),
      if (_source == _VideoSource.link)
        TextFormField(
          controller: _videoUrl,
          keyboardType: TextInputType.url,
          validator: _validateUrl,
          decoration: const InputDecoration(
            labelText: 'Đường dẫn video',
            prefixIcon: Icon(Icons.link_rounded),
            border: OutlineInputBorder(),
          ),
        )
      else if (_video == null) ...[
        OutlinedButton.icon(
          onPressed: _pickVideo,
          style:
              OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          icon: const Icon(Icons.video_library_outlined),
          label: const Text('Chọn video'),
        ),
        const SizedBox(height: 6),
        Text(
          'MP4, MOV hoặc WEBM · tối đa 200 MB',
          style:
              context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
        ),
      ] else
        _UploadCard(
          video: _video!,
          phase: _phase,
          progress: _progress,
          error: _uploadError,
          onCancel: _cancelUpload,
          onRetry: _startUpload,
          onPickAnother: _pickVideo,
        ),
    ];
  }
}

/// The picked file and where its upload stands.
class _UploadCard extends StatelessWidget {
  const _UploadCard({
    required this.video,
    required this.phase,
    required this.progress,
    required this.error,
    required this.onCancel,
    required this.onRetry,
    required this.onPickAnother,
  });

  final PickedVideo video;
  final _UploadPhase phase;
  final double progress;
  final String? error;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onPickAnother;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final failed =
        phase == _UploadPhase.failed || phase == _UploadPhase.invalid;
    return VLCard(
      borderColor: failed ? context.colors.error : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.movie_outlined, color: context.colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(video.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.titleSmall),
                    Text(video.summary,
                        style: context.textStyles.bodySmall
                            ?.copyWith(color: vl.muted)),
                  ],
                ),
              ),
              if (phase == _UploadPhase.done)
                Icon(Icons.check_circle_rounded, color: vl.success),
            ],
          ),
          const SizedBox(height: 12),
          switch (phase) {
            _UploadPhase.uploading || _UploadPhase.idle => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(999),
                    semanticsLabel: 'Tiến độ tải video',
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
                      onPressed: onPickAnother, child: const Text('Đổi video')),
                ],
              ),
            _UploadPhase.failed || _UploadPhase.invalid => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(error ?? 'Chưa tải lên được video.',
                      style: context.textStyles.bodyMedium
                          ?.copyWith(color: context.colors.error)),
                  Wrap(
                    spacing: 4,
                    children: [
                      if (phase == _UploadPhase.failed)
                        TextButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Thử lại'),
                        ),
                      TextButton(
                          onPressed: onPickAnother,
                          child: const Text('Chọn video khác')),
                    ],
                  ),
                ],
              ),
          },
        ],
      ),
    );
  }
}

/// Edit mode: the video can't be swapped on an existing post.
class _PostedVideoCard extends StatelessWidget {
  const _PostedVideoCard({required this.post});

  final Post post;

  @override
  Widget build(BuildContext context) {
    final seconds = post.videoDurationSeconds;
    return VLCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.videocam_outlined, color: context.colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  seconds == null || seconds <= 0
                      ? 'Video đã đăng'
                      : 'Video đã đăng · ${formatDuration(seconds)}',
                  style: context.textStyles.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Không đổi được video khi sửa bài. Muốn đổi video, hãy xoá bài và đăng lại.',
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
