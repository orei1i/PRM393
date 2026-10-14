// lib/features/chatbot/presentation/widgets/guest_trial_banner.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';

/// "Bạn còn 2/3 lượt hỏi miễn phí" + sign-in shortcut. Announced on change.
class GuestTrialBanner extends StatelessWidget {
  const GuestTrialBanner({super.key, required this.remaining, required this.limit, required this.onSignIn});

  final int remaining;
  final int limit;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final exhausted = remaining <= 0;

    return Semantics(
      liveRegion: true,
      label: exhausted
          ? 'Bạn đã dùng hết $limit lượt hỏi miễn phí'
          : 'Bạn còn $remaining trên $limit lượt hỏi miễn phí',
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: exhausted ? vl.cautionContainer : vl.aiContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: exhausted ? vl.cautionBorder : vl.aiBorder),
        ),
        child: Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: exhausted ? vl.onCautionContainer : vl.onAiContainer),
            const SizedBox(width: 10),
            Expanded(
              child: ExcludeSemantics(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                  child: Text.rich(
                    key: ValueKey(remaining),
                    TextSpan(
                      style: context.textStyles.bodyMedium,
                      children: exhausted
                          ? const [TextSpan(text: 'Đã hết lượt hỏi miễn phí')]
                          : [
                              const TextSpan(text: 'Còn '),
                              TextSpan(
                                text: '$remaining/$limit',
                                style: AppTypography.mono(size: 14, weight: FontWeight.w700, color: vl.onAiContainer),
                              ),
                              const TextSpan(text: ' lượt hỏi miễn phí'),
                            ],
                    ),
                  ),
                ),
              ),
            ),
            TextButton(onPressed: onSignIn, child: const Text('Đăng nhập')),
          ],
        ),
      ),
    );
  }
}
