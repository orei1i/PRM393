// lib/features/video/presentation/widgets/video_recipe_sheet.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../data/video_api_service.dart';
import '../../domain/entities/video_recipe.dart';
import 'ai_pipeline_status.dart';

/// "Xem công thức" on a video post or a reel: the AI recipe in a bottom
/// sheet (85 % of the screen, drag down to close) over the player. Tapping
/// a timestamp calls [onSeek] and closes the sheet so the video plays from
/// there. Resolves when the sheet is closed.
Future<void> showVideoRecipeSheet(
  BuildContext context, {
  required String videoId,
  String? title,
  ValueChanged<int>? onSeek,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          VideoRecipeSheet(videoId: videoId, title: title, onSeek: onSeek),
    );

/// Tabs "Tóm tắt AI · Nguyên liệu · Các bước · Lời thoại", "Sao chép danh
/// sách đi chợ" and the AI disclaimer. While the server pipeline runs it
/// shows its progress (polled every 3 s); a failed extraction shows "AI chưa
/// tóm tắt được video".
class VideoRecipeSheet extends ConsumerStatefulWidget {
  const VideoRecipeSheet(
      {super.key, required this.videoId, this.title, this.onSeek});

  final String videoId;

  /// Shown until the video loads.
  final String? title;

  /// `null` hides the timestamps' play action (nothing to seek).
  final ValueChanged<int>? onSeek;

  static const tabLabels = [
    'Tóm tắt AI',
    'Nguyên liệu',
    'Các bước',
    'Lời thoại'
  ];

  @override
  ConsumerState<VideoRecipeSheet> createState() => _VideoRecipeSheetState();
}

class _VideoRecipeSheetState extends ConsumerState<VideoRecipeSheet> {
  VideoRecipe? _video;
  Object? _error;
  Timer? _poll;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _copiedTimer?.cancel();
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
      _poll?.cancel();
      if (video.status.isProcessing) {
        _poll = Timer(const Duration(seconds: 3), _load);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _seek(int second) {
    widget.onSeek?.call(second);
    Navigator.of(context).maybePop();
  }

  Future<void> _copyShoppingList(VideoRecipe video) async {
    final text = [
      'Đi chợ: ${video.title}',
      for (final i in video.ingredients) '- ${i.name}: ${i.quantity}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final onSeek = widget.onSeek == null ? null : _seek;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const AiBadge(label: 'Công thức từ video'),
                      const SizedBox(height: 6),
                      Text(
                        video?.title ?? widget.title ?? 'Công thức',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.textStyles.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch ((video, _error)) {
              (null, final Object error) => Center(
                  child: SingleChildScrollView(
                      child: ErrorStateView(error: error, onRetry: _load))),
              (null, _) => const Center(child: CircularProgressIndicator()),
              (final VideoRecipe v, _) when v.status.isProcessing => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [AiPipelineStatus(status: v.status)],
                ),
              (final VideoRecipe v, _) when v.status == VideoAiStatus.failed =>
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [_FailedCard(reason: v.failureReason)],
                ),
              (final VideoRecipe v, _) => _RecipeTabs(
                  video: v,
                  onSeek: onSeek,
                  copied: _copied,
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
  const _FailedCard({required this.reason});

  final String? reason;

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
              Expanded(
                child: Text('AI chưa tóm tắt được video',
                    style: context.textStyles.titleMedium
                        ?.copyWith(color: context.vl.onCautionContainer)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            reason ?? 'Đã có lỗi khi xử lý video.',
            style: context.textStyles.bodyMedium
                ?.copyWith(color: context.vl.onCautionContainer),
          ),
        ],
      ),
    );
  }
}

class _RecipeTabs extends StatelessWidget {
  const _RecipeTabs({
    required this.video,
    required this.onSeek,
    required this.copied,
    required this.onCopyShoppingList,
  });

  final VideoRecipe video;
  final ValueChanged<int>? onSeek;
  final bool copied;
  final VoidCallback onCopyShoppingList;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: VideoRecipeSheet.tabLabels.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final t in VideoRecipeSheet.tabLabels) Tab(text: t)],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _SummaryTab(
                    video: video,
                    copied: copied,
                    onCopyShoppingList: onCopyShoppingList),
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
  const _SummaryTab({
    required this.video,
    required this.copied,
    required this.onCopyShoppingList,
  });

  final VideoRecipe video;
  final bool copied;
  final VoidCallback onCopyShoppingList;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom),
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
          icon: Icon(
              copied ? Icons.check_rounded : Icons.shopping_basket_outlined),
          label: Text(copied
              ? 'Đã sao chép danh sách đi chợ'
              : 'Sao chép danh sách đi chợ'),
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
  final ValueChanged<int>? onSeek;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: video.ingredients.length,
      separatorBuilder: (_, __) => const Divider(indent: 16, endIndent: 16),
      itemBuilder: (context, i) {
        final item = video.ingredients[i];
        final at = item.atSecond;
        return ListTile(
          title: Text(item.name, style: context.textStyles.titleSmall),
          subtitle: Row(
            children: [
              Flexible(child: Text(item.quantity)),
              if (item.uncertain) ...[
                const SizedBox(width: 8),
                VLTag.caution(context, 'AI chưa chắc'),
              ],
            ],
          ),
          trailing: at == null || onSeek == null
              ? null
              : _TimeChip(second: at, onSeek: onSeek!),
        );
      },
    );
  }
}

class _StepsTab extends StatelessWidget {
  const _StepsTab({required this.video, required this.onSeek});

  final VideoRecipe video;
  final ValueChanged<int>? onSeek;

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
                    if (onSeek != null) ...[
                      const SizedBox(height: 4),
                      _TimeChip(second: step.atSecond, onSeek: onSeek!),
                    ],
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
  final ValueChanged<int>? onSeek;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: video.transcript.length,
      itemBuilder: (context, i) {
        final seg = video.transcript[i];
        return InkWell(
          onTap: onSeek == null ? null : () => onSeek!(seg.atSecond),
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

/// Re-runs the extraction for a failed video ("Thử trích xuất lại", the
/// author only). Shows a snackbar on failure; `true` when it restarted.
Future<bool> retryVideoExtraction(
    BuildContext context, WidgetRef ref, String videoId) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref.read(videoApiProvider).retryExtraction(videoId);
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(describeError(e))));
    return false;
  }
}
