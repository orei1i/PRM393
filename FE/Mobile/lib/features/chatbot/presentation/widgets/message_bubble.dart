// lib/features/chatbot/presentation/widgets/message_bubble.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../domain/entities/chat_message.dart';
import 'citation_drawer.dart';
import 'citation_pill.dart';
import 'typing_indicator.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble(
      {super.key, required this.message, this.onRetry, this.onFeedback});

  final ChatMessage message;
  final VoidCallback? onRetry;
  final void Function(bool helpful)? onFeedback;

  @override
  Widget build(BuildContext context) {
    return message.isUser
        ? _UserBubble(message: message)
        : _AssistantMessage(
            message: message, onRetry: onRetry, onFeedback: onFeedback);
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: message.content));
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã sao chép câu hỏi')));
        },
        child: Container(
          constraints:
              BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: Text(message.content,
              style:
                  context.textStyles.bodyLarge?.copyWith(color: cs.onPrimary)),
        ),
      ),
    );
  }
}

class _AssistantMessage extends StatelessWidget {
  const _AssistantMessage(
      {required this.message, this.onRetry, this.onFeedback});

  final ChatMessage message;
  final VoidCallback? onRetry;
  final void Function(bool helpful)? onFeedback;

  static final _citationPattern = RegExp(r'\[(\d+)\](?!\()');

  /// "[1]" → markdown link "[\[1\]](cite:1)" so citations are tappable inline.
  static String _linkCitations(String text) => text.replaceAllMapped(
      _citationPattern, (m) => '[\\[${m[1]}\\]](cite:${m[1]})');

  void _onTapLink(BuildContext context, String? href) {
    if (href == null || !href.startsWith('cite:')) return;
    final index = int.tryParse(href.substring(5));
    for (final c in message.citations) {
      if (c.index == index) {
        showCitationDrawer(context, c);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final text = context.textStyles;
    final status = message.status;

    final styleSheet = MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: text.bodyLarge,
      strong: text.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
      listBullet: text.bodyLarge,
      a: text.labelMedium
          ?.copyWith(color: vl.onAiContainer, fontWeight: FontWeight.w800),
      blockSpacing: 10,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 16, color: vl.ai),
            const SizedBox(width: 6),
            Text('VeganLife AI',
                style: text.labelMedium?.copyWith(color: vl.onAiContainer)),
            if (message.citations.isNotEmpty) ...[
              Text(' · ${message.citations.length} nguồn',
                  style: text.labelMedium?.copyWith(color: vl.muted)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (status == MessageStatus.waiting)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: TypingIndicator())
        else if (message.content.isNotEmpty)
          MarkdownBody(
            data: _linkCitations(message.content),
            styleSheet: styleSheet,
            onTapLink: (text, href, title) => _onTapLink(context, href),
          ),
        if (status == MessageStatus.streaming)
          const Padding(
              padding: EdgeInsets.only(top: 4), child: StreamingCaret()),
        if (message.citations.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in message.citations) CitationPill(citation: c)
            ],
          ),
        ],
        if (status == MessageStatus.interrupted ||
            status == MessageStatus.failed)
          _InterruptedBanner(message: message, onRetry: onRetry),
        if (status == MessageStatus.complete) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                tooltip: 'Hữu ích',
                onPressed: onFeedback == null ? null : () => onFeedback!(true),
                icon: const Icon(Icons.thumb_up_alt_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Chưa hữu ích',
                onPressed: onFeedback == null ? null : () => onFeedback!(false),
                icon: const Icon(Icons.thumb_down_alt_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Sao chép',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Đã sao chép câu trả lời')));
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
              ),
            ],
          ),
          Text(
            'Không thay thế tư vấn của bác sĩ hoặc chuyên gia dinh dưỡng.',
            style: text.bodySmall?.copyWith(color: vl.muted),
          ),
        ],
      ],
    );
  }
}

class _InterruptedBanner extends StatelessWidget {
  const _InterruptedBanner({required this.message, this.onRetry});

  final ChatMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final partial = message.status == MessageStatus.interrupted;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        border: Border.all(color: vl.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_off_rounded, size: 18, color: vl.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message.errorMessage ?? 'Câu trả lời bị gián đoạn.',
                  style: context.textStyles.labelLarge,
                ),
              ),
            ],
          ),
          if (partial)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Phần đã nhận được giữ nguyên. "Tiếp tục" sẽ viết tiếp từ chỗ dừng.',
                style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
              ),
            ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(partial ? 'Tiếp tục từ đây' : 'Thử lại'),
          ),
        ],
      ),
    );
  }
}
