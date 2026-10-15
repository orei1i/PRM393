// lib/features/video/presentation/screens/video_detail_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../community/domain/entities/post.dart';
import '../../../community/presentation/controllers/feed_controller.dart';
import '../../data/video_api_service.dart';
import '../../domain/entities/video_recipe.dart';
import '../widgets/ai_pipeline_status.dart';
import '../widgets/video_player_view.dart';

/// Cooking video + AI-extracted recipe (summary, ingredients, steps, transcript).
/// Polls every 3 s while the server pipeline is still running.
class VideoDetailScreen extends ConsumerStatefulWidget {
  const VideoDetailScreen({super.key, required this.videoId, this.post});

  final String videoId;

  /// Feed post that opened this screen (title/author shown before load).
  final Post? post;

  static Route<void> route(String videoId, {Post? post}) =>
      MaterialPageRoute<void>(
          builder: (_) => VideoDetailScreen(videoId: videoId, post: post));

  @override
  ConsumerState<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends ConsumerState<VideoDetailScreen> {
  final _player = GlobalKey<VideoPlayerViewState>();
  VideoRecipe? _video;
  Object? _error;
  Timer? _poll;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final video = (await ref.read(videoApiProvider).getVideo(widget.videoId))
          .toEntity();
      if (!mounted) return;
      setState(() {
        _video = video;
        _error = null;
      });
      ref
          .read(feedControllerProvider.notifier)
          .videoStatusChanged(video.id, video.status);
      _poll?.cancel();
      if (video.status.isProcessing) {
        _poll = Timer(const Duration(seconds: 3), _load);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await ref.read(videoApiProvider).retryExtraction(widget.videoId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describeError(e))));
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  void _seek(int second) =>
      _player.currentState?.seekTo(Duration(seconds: second));

  Future<void> _copyShoppingList(VideoRecipe video) async {
    final text = [
      'Đi chợ: ${video.title}',
      for (final i in video.ingredients) '- ${i.name}: ${i.quantity}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Đã sao chép danh sách nguyên liệu để đi chợ.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final title = video?.title ?? widget.post?.title ?? 'Video công thức';
    final author = video?.author ?? widget.post?.author;

    return Scaffold(
      appBar: AppBar(title: const Text('Video công thức')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VideoPlayerView(
            key: _player,
            url: video?.videoUrl,
            coverSeed:
                video?.coverSeed ?? widget.post?.coverSeed ?? widget.videoId,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: context.textStyles.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                if (author != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      UserAvatar(
                          name: author.name,
                          size: 28,
                          verified: author.isVerifiedChef),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(author.name,
                              style: context.textStyles.labelLarge)),
                      if (video != null)
                        Text(formatDuration(video.durationSeconds),
                            style: context.textStyles.bodySmall
                                ?.copyWith(color: context.vl.muted)),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: switch ((video, _error)) {
              (null, final Object error) =>
                Center(child: ErrorStateView(error: error, onRetry: _load)),
              (null, _) => const Center(child: CircularProgressIndicator()),
              (final VideoRecipe v, _) when v.status.isProcessing => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [AiPipelineStatus(status: v.status)],
                ),
              (final VideoRecipe v, _) when v.status == VideoAiStatus.failed =>
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _FailedCard(
                        reason: v.failureReason,
                        retrying: _retrying,
                        onRetry: _retry)
                  ],
                ),
              (final VideoRecipe v, _) => _RecipeTabs(
                  video: v,
                  onSeek: _seek,
                  onCopyShoppingList: () => _copyShoppingList(v),
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _FailedCard extends StatelessWidget {
  const _FailedCard(
      {required this.reason, required this.retrying, required this.onRetry});

  final String? reason;
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return VLCard(
      color: context.vl.cautionContainer,
      borderColor: context.vl.cautionBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hearing_disabled_outlined,
                  color: context.vl.onCautionContainer),
              const SizedBox(width: 8),
              Text('AI chưa tóm tắt được video',
                  style: context.textStyles.titleMedium
                      ?.copyWith(color: context.vl.onCautionContainer)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reason ?? 'Đã có lỗi khi xử lý video.',
            style: context.textStyles.bodyMedium
                ?.copyWith(color: context.vl.onCautionContainer),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: retrying ? null : onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(retrying ? 'Đang gửi lại…' : 'Thử trích xuất lại'),
          ),
        ],
      ),
    );
  }
}

class _RecipeTabs extends StatelessWidget {
  const _RecipeTabs(
      {required this.video,
      required this.onSeek,
      required this.onCopyShoppingList});

  final VideoRecipe video;
  final ValueChanged<int> onSeek;
  final VoidCallback onCopyShoppingList;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Tóm tắt AI'),
              Tab(text: 'Nguyên liệu'),
              Tab(text: 'Các bước'),
              Tab(text: 'Lời thoại'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _SummaryTab(
                    video: video, onCopyShoppingList: onCopyShoppingList),
                _IngredientsTab(video: video, onSeek: onSeek),
                _StepsTab(video: video, onSeek: onSeek),
                _TranscriptTab(video: video, onSeek: onSeek),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTab extends StatelessWidget {
  const _SummaryTab({required this.video, required this.onCopyShoppingList});

  final VideoRecipe video;
  final VoidCallback onCopyShoppingList;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        VLCard(
          color: context.vl.aiContainer,
          borderColor: context.vl.aiBorder,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AiBadge(label: 'Tóm tắt bởi AI'),
              const SizedBox(height: 10),
              Text(video.summary ?? '',
                  style: context.textStyles.bodyLarge?.copyWith(height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _Fact(
                icon: Icons.people_outline_rounded,
                label: 'Khẩu phần',
                value: '${video.servings ?? '–'}'),
            const SizedBox(width: 8),
            _Fact(
                icon: Icons.timer_outlined,
                label: 'Thời gian',
                value: '${video.totalMinutes ?? '–'} phút'),
            const SizedBox(width: 8),
            _Fact(
              icon: Icons.local_fire_department_outlined,
              label: 'kcal/phần',
              value: video.kcalPerServing == null
                  ? '–'
                  : formatInt(video.kcalPerServing!),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: video.ingredients.isEmpty ? null : onCopyShoppingList,
          icon: const Icon(Icons.shopping_basket_outlined),
          label: const Text('Sao chép danh sách đi chợ'),
        ),
        const SizedBox(height: 12),
        Text(
          'Nội dung do AI tạo từ lời thoại. Mục tô màu cam là chỗ AI nghe chưa rõ — hãy xem lại đoạn video tương ứng.',
          style:
              context.textStyles.bodySmall?.copyWith(color: context.vl.muted),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: VLCard(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Column(
          children: [
            Icon(icon, color: context.colors.primary),
            const SizedBox(height: 6),
            Text(value,
                style: context.textStyles.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text(label,
                style: context.textStyles.bodySmall
                    ?.copyWith(color: context.vl.muted)),
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.second, required this.onSeek});

  final int second;
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.play_arrow_rounded, size: 16),
      label: Text(formatDuration(second)),
      tooltip: 'Tua đến ${formatDuration(second)}',
      onPressed: () => onSeek(second),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _IngredientsTab extends StatelessWidget {
  const _IngredientsTab({required this.video, required this.onSeek});

  final VideoRecipe video;
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: video.ingredients.length,
      separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
      itemBuilder: (context, i) {
        final item = video.ingredients[i];
        return ListTile(
          title: Text(item.name, style: context.textStyles.titleSmall),
          subtitle: Row(
            children: [
              Text(item.quantity),
              if (item.uncertain) ...[
                const SizedBox(width: 8),
                VLTag.caution(context, 'AI chưa chắc'),
              ],
            ],
          ),
          trailing: item.atSecond == null
              ? null
              : _TimeChip(second: item.atSecond!, onSeek: onSeek),
        );
      },
    );
  }
}

class _StepsTab extends StatelessWidget {
  const _StepsTab({required this.video, required this.onSeek});

  final VideoRecipe video;
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: video.steps.length,
      itemBuilder: (context, i) {
        final step = video.steps[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: context.colors.primaryContainer,
                foregroundColor: context.colors.onPrimaryContainer,
                child: Text('${step.index}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.text,
                        style: context.textStyles.bodyLarge
                            ?.copyWith(height: 1.45)),
                    const SizedBox(height: 4),
                    _TimeChip(second: step.atSecond, onSeek: onSeek),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TranscriptTab extends StatelessWidget {
  const _TranscriptTab({required this.video, required this.onSeek});

  final VideoRecipe video;
  final ValueChanged<int> onSeek;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: video.transcript.length,
      itemBuilder: (context, i) {
        final seg = video.transcript[i];
        return InkWell(
          onTap: () => onSeek(seg.atSecond),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 52,
                  child: Text(
                    formatDuration(seg.atSecond),
                    style: context.textStyles.labelMedium
                        ?.copyWith(color: context.colors.primary),
                  ),
                ),
                Expanded(
                    child:
                        Text(seg.text, style: context.textStyles.bodyMedium)),
              ],
            ),
          ),
        );
      },
    );
  }
}
