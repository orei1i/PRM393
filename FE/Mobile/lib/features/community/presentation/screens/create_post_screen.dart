// lib/features/community/presentation/screens/create_post_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../data/community_api_service.dart';
import '../../data/models/post_model.dart';
import '../../domain/entities/post.dart';

/// Composer for discussion / recipe / video-link posts. Pops the created [Post].
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  static Route<Post> route() => MaterialPageRoute<Post>(
        fullscreenDialog: true,
        builder: (_) => const CreatePostScreen(),
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

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _videoUrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      final dto = await ref.read(communityApiProvider).createPost(
            CreatePostRequestDto(
              type: _type,
              title: _title.text.trim(),
              body: _body.text.trim(),
              tags: _tags.toList(),
              videoUrl: _type == PostType.video ? _videoUrl.text.trim() : null,
            ),
          );
      if (mounted) Navigator.of(context).pop(dto.toEntity());
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  String? _validateTitle(String? v) {
    final text = v?.trim() ?? '';
    if (text.length < 8) return 'Tiêu đề cần ít nhất 8 ký tự.';
    if (text.length > 120) return 'Tiêu đề tối đa 120 ký tự.';
    return null;
  }

  String? _validateUrl(String? v) {
    if (_type != PostType.video) return null;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tạo bài viết'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
              child: Text(_submitting ? 'Đang đăng…' : 'Đăng'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
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
              onSelectionChanged: (s) => setState(() => _type = s.first),
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
              TextFormField(
                controller: _videoUrl,
                keyboardType: TextInputType.url,
                validator: _validateUrl,
                decoration: const InputDecoration(
                  labelText: 'Đường dẫn video',
                  prefixIcon: Icon(Icons.link_rounded),
                  border: OutlineInputBorder(),
                ),
              ),
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
}
