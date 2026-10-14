// lib/features/chatbot/presentation/widgets/citation_drawer.dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/chat_message.dart';

IconData citationIcon(CitationSourceType type) => switch (type) {
      CitationSourceType.scientific => Icons.science_outlined,
      CitationSourceType.chefDocument => Icons.restaurant_menu_rounded,
      CitationSourceType.userData => Icons.person_outline_rounded,
    };

/// Source detail: who said it, the retrieved passage, and a link out.
Future<void> showCitationDrawer(BuildContext context, Citation citation) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CitationDrawer(citation: citation),
  );
}

class _CitationDrawer extends StatelessWidget {
  const _CitationDrawer({required this.citation});

  final Citation citation;

  Future<void> _open(BuildContext context) async {
    final url = citation.url;
    if (url == null) return;
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không mở được liên kết.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: vl.aiContainer, shape: BoxShape.circle),
                child: Text('${citation.index}', style: AppTypography.mono(size: 13, color: vl.onAiContainer)),
              ),
              const SizedBox(width: 10),
              Icon(citationIcon(citation.sourceType), size: 18, color: vl.muted),
              const SizedBox(width: 6),
              Text(citation.sourceType.label, style: context.textStyles.labelMedium?.copyWith(color: vl.muted)),
              if (citation.verified) ...[
                const SizedBox(width: 8),
                Icon(Icons.verified_rounded, size: 16, color: context.colors.primary),
                const SizedBox(width: 4),
                Text('Đã xác minh', style: context.textStyles.labelMedium?.copyWith(color: context.colors.primary)),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Text(citation.title, style: context.textStyles.titleLarge),
          const SizedBox(height: 4),
          Text(
            citation.publishedAt == null
                ? citation.publisher
                : '${citation.publisher} · ${formatDayMonth(citation.publishedAt!)}/${citation.publishedAt!.year}',
            style: context.textStyles.bodyMedium?.copyWith(color: vl.muted),
          ),
          const SizedBox(height: 16),
          Text('Đoạn được trích dẫn', style: context.textStyles.labelLarge),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: vl.aiContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.format_quote_rounded, color: vl.onAiContainer),
                const SizedBox(width: 8),
                Expanded(child: SelectableText(citation.passage, style: context.textStyles.bodyLarge)),
              ],
            ),
          ),
          if (citation.sourceType == CitationSourceType.chefDocument) ...[
            const SizedBox(height: 10),
            Text(
              'Tài liệu của đầu bếp chỉ được dùng để trả lời sau khi quản trị viên phê duyệt.',
              style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
            ),
          ],
          if (citation.url != null) ...[
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () => _open(context),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Mở nguồn gốc'),
            ),
          ],
        ],
      ),
    );
  }
}
