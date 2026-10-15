// lib/features/chatbot/presentation/widgets/chat_composer.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';

/// Quick prompts + input. Send turns into Stop while an answer streams.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.isStreaming,
    required this.onSend,
    required this.onStop,
    required this.quickPrompts,
    this.showQuickPrompts = true,
  });

  final bool isStreaming;
  final ValueChanged<String> onSend;
  final VoidCallback onStop;
  final List<String> quickPrompts;
  final bool showQuickPrompts;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? text]) {
    final value = (text ?? _controller.text).trim();
    if (value.isEmpty || widget.isStreaming) return;
    widget.onSend(value);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final vl = context.vl;
    final canSend = _controller.text.trim().isNotEmpty && !widget.isStreaming;

    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showQuickPrompts && widget.quickPrompts.isNotEmpty)
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.quickPrompts.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final prompt = widget.quickPrompts[i];
                      // Bounded so the chip measures its label with the
                      // loaded font, not stale metrics (clipped labels).
                      return ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width - 32),
                        child: ActionChip(
                          label: Text(prompt),
                          avatar:
                              Icon(Icons.auto_awesome, size: 16, color: vl.ai),
                          onPressed:
                              widget.isStreaming ? null : () => _submit(prompt),
                        ),
                      );
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 2, 4, 2),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: cs.outline),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            hintText: 'Hỏi về dinh dưỡng, công thức…',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: widget.isStreaming
                            ? IconButton.filledTonal(
                                tooltip: 'Dừng trả lời',
                                onPressed: widget.onStop,
                                style: IconButton.styleFrom(
                                    minimumSize: const Size(44, 44)),
                                icon: const Icon(Icons.stop_rounded),
                              )
                            : IconButton.filled(
                                tooltip: 'Gửi',
                                onPressed: canSend ? _submit : null,
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(44, 44),
                                  backgroundColor: cs.tertiary,
                                  foregroundColor: cs.onTertiary,
                                ),
                                icon: const Icon(Icons.arrow_upward_rounded),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
