// lib/features/chatbot/presentation/widgets/typing_indicator.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';

/// Three pulsing dots shown before the first token arrives.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, this.label = 'Đang tìm nguồn và soạn câu trả lời'});

  final String label;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.vl.ai;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      liveRegion: true,
      label: widget.label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_controller.value - i * 0.18) % 1.0;
                final t = reduceMotion ? 1.0 : 0.35 + 0.65 * (0.5 + 0.5 * math.sin(phase * 2 * math.pi));
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: t.clamp(0.0, 1.0).toDouble()),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(widget.label, style: context.textStyles.bodySmall?.copyWith(color: context.vl.muted)),
          ),
        ],
      ),
    );
  }
}

/// Blinking caret appended to a streaming answer.
class StreamingCaret extends StatefulWidget {
  const StreamingCaret({super.key});

  @override
  State<StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<StreamingCaret> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(width: 8, height: 16, color: context.vl.ai),
    );
  }
}
