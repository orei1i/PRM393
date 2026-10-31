// lib/features/meal_planner/presentation/widgets/allergy_guard_banner.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/labels.dart';
import '../../domain/entities/meal_plan.dart';

/// Over the selected day's meals. An ochre alert when one contains the user's
/// allergens, whoever chose it. Otherwise neutral, and it only speaks for what
/// AI chose: nothing at all ([shownFor]) on a day of hand-picked, typed-in or
/// chef's dishes, and only about the AI's dishes on a mixed day.
class AllergyGuardBanner extends StatelessWidget {
  const AllergyGuardBanner({
    super.key,
    required this.allergies,
    required this.conflictCount,
    this.allAi = true,
  });

  final List<String> allergies;
  final int conflictCount;

  /// Every meal of the day came from AI.
  final bool allAi;

  /// Whether [day] has anything for this banner to say.
  static bool shownFor(MealPlanDay day, Iterable<String> allergies) =>
      day.conflictCount(allergies) > 0 ||
      day.meals.values.any((r) => r.source == MealSource.ai);

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final hasConflict = conflictCount > 0;
    final names = allergies.map(allergenLabel).join(', ');

    final message = hasConflict
        ? '$conflictCount món hôm nay có thể chứa chất bạn dị ứng ($names). '
            'Hãy đổi món hoặc kiểm tra kỹ trước khi nấu.'
        : !allAi
            ? allergies.isEmpty
                ? 'Một số món do AI gợi ý. Luôn đọc nhãn thành phần trước khi nấu.'
                : 'Món do AI gợi ý đã loại trừ: $names. Các món khác hãy tự kiểm tra; luôn đọc nhãn thành phần trước khi nấu.'
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
