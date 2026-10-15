// lib/features/community/presentation/widgets/video_status_chip.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../video/domain/entities/video_recipe.dart';

/// Lavender "AI" chip on video covers: summary ready / processing / failed.
class VideoStatusChip extends StatelessWidget {
  const VideoStatusChip({super.key, required this.status});

  final VideoAiStatus status;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final (Color bg, Color fg, String label) = switch (status) {
      VideoAiStatus.ready => (vl.aiContainer, vl.onAiContainer, 'Tóm tắt AI'),
      VideoAiStatus.failed => (
          vl.cautionContainer,
          vl.onCautionContainer,
          'AI chưa xử lý được'
        ),
      _ => (vl.aiContainer, vl.onAiContainer, 'AI đang xử lý…'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.isProcessing)
            SizedBox.square(
                dimension: 11,
                child: CircularProgressIndicator(strokeWidth: 1.6, color: fg))
          else
            Icon(
                status == VideoAiStatus.failed
                    ? Icons.error_outline_rounded
                    : Icons.auto_awesome,
                size: 13,
                color: fg),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: fg, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
