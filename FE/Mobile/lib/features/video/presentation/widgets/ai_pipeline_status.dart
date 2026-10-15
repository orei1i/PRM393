// lib/features/video/presentation/widgets/ai_pipeline_status.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/video_recipe.dart';

/// Upload → speech-to-text → extraction progress, shown while the summary
/// isn't ready. Each stage: done ✓ / running (spinner) / waiting.
class AiPipelineStatus extends StatelessWidget {
  const AiPipelineStatus({super.key, required this.status});

  final VideoAiStatus status;

  static const _stages = [
    (VideoAiStatus.queued, 'Nhận video', 'Video đã vào hàng chờ xử lý'),
    (
      VideoAiStatus.transcribing,
      'Nhận dạng giọng nói',
      'Chuyển lời thoại tiếng Việt thành văn bản'
    ),
    (
      VideoAiStatus.extracting,
      'Trích xuất công thức',
      'Tách nguyên liệu, định lượng, từng bước + mốc thời gian'
    ),
    (VideoAiStatus.ready, 'Hoàn tất', 'Tóm tắt sẵn sàng để lưu vào thực đơn'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _stages.indexWhere((s) => s.$1 == status);
    return VLCard(
      color: context.vl.aiContainer,
      borderColor: context.vl.aiBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: context.vl.ai),
              const SizedBox(width: 8),
              Text('AI đang tóm tắt video',
                  style: context.textStyles.titleMedium
                      ?.copyWith(color: context.vl.onAiContainer)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Bạn có thể rời màn hình này — kết quả sẽ có trong bài đăng.',
            style: context.textStyles.bodySmall
                ?.copyWith(color: context.vl.onAiContainer),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < _stages.length; i++)
            _StageRow(
              title: _stages[i].$2,
              subtitle: _stages[i].$3,
              state: i < current
                  ? _StageState.done
                  : (i == current ? _StageState.running : _StageState.waiting),
              last: i == _stages.length - 1,
            ),
        ],
      ),
    );
  }
}

enum _StageState { done, running, waiting }

class _StageRow extends StatelessWidget {
  const _StageRow(
      {required this.title,
      required this.subtitle,
      required this.state,
      required this.last});

  final String title;
  final String subtitle;
  final _StageState state;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final Widget marker = switch (state) {
      _StageState.done =>
        Icon(Icons.check_circle_rounded, size: 22, color: vl.success),
      _StageState.running => SizedBox.square(
          dimension: 22,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: CircularProgressIndicator(strokeWidth: 2.4, color: vl.ai),
          ),
        ),
      _StageState.waiting =>
        Icon(Icons.radio_button_unchecked_rounded, size: 22, color: vl.muted),
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              marker,
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: state == _StageState.done ? vl.success : vl.aiBorder,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.textStyles.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: state == _StageState.waiting
                          ? vl.muted
                          : vl.onAiContainer,
                    ),
                  ),
                  Text(subtitle,
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: vl.muted)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
