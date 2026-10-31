// lib/features/ingredient/presentation/widgets/not_vegan_notice.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../scanner/domain/vegan_check.dart';

/// "Trứng gà không thuần chay nên không thêm vào tủ." with the reason and
/// the vegan swaps; tapping a swap adds it instead. [destination] is where the
/// food was going ("tủ", "thực đơn").
class NotVeganNotice extends StatelessWidget {
  const NotVeganNotice(
      {super.key,
      required this.name,
      required this.verdict,
      required this.onPick,
      this.destination = 'tủ'});

  final String name;
  final VeganVerdict verdict;
  final ValueChanged<String>? onPick;
  final String destination;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.block_rounded, size: 18, color: cs.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$name không thuần chay nên không thêm vào $destination.',
                    style: context.textStyles.bodyMedium?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (verdict.nonVeganReason case final reason?)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 2),
                child: Text(reason,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: cs.onErrorContainer)),
              ),
            if (verdict.veganAlternatives.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 26, top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Gợi ý thay thế:',
                        style: context.textStyles.bodySmall?.copyWith(
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.w700)),
                    for (final alternative in verdict.veganAlternatives)
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 16),
                        label: Text(alternative),
                        tooltip:
                            'Thêm ${alternative.toLowerCase()} vào $destination',
                        backgroundColor: cs.surface,
                        onPressed:
                            onPick == null ? null : () => onPick!(alternative),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
