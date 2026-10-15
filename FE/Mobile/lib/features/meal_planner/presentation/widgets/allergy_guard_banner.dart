// lib/features/meal_planner/presentation/widgets/allergy_guard_banner.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/labels.dart';

/// Always shown on AI-generated plans. Neutral when clear; ochre alert when a
/// meal of the selected day contains one of the user's allergens.
class AllergyGuardBanner extends StatelessWidget {
  const AllergyGuardBanner(
      {super.key, required this.allergies, required this.conflictCount});

  final List<String> allergies;
  final int conflictCount;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final hasConflict = conflictCount > 0;
    final names = allergies.map(allergenLabel).join(', ');

    final message = hasConflict
        ? '$conflictCount món hôm nay có thể chứa chất bạn dị ứng ($names). '
            'Hãy đổi món hoặc kiểm tra kỹ trước khi nấu.'
        : allergies.isEmpty
            ? 'Thực đơn do AI tạo. Luôn đọc nhãn thành phần trước khi nấu.'
            : 'Thực đơn do AI tạo, đã loại trừ: $names. Luôn đọc nhãn thành phần trước khi nấu.';

    return Semantics(
      liveRegion: hasConflict,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: hasConflict
              ? vl.cautionContainer
              : context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hasConflict ? vl.cautionBorder : vl.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              hasConflict ? Icons.warning_amber_rounded : Icons.shield_outlined,
              size: 18,
              color: hasConflict ? vl.onCautionContainer : vl.muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: context.textStyles.bodySmall?.copyWith(
                  color: hasConflict ? vl.onCautionContainer : vl.muted,
                  fontWeight: hasConflict ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
