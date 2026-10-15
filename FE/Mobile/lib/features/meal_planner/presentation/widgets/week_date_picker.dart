// lib/features/meal_planner/presentation/widgets/week_date_picker.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/meal_plan.dart';

/// 7 day pills (T2 … CN). The dot under each day shows calorie fit:
/// green = within ±10 % of target, ochre = over, hollow = under.
class WeekDatePicker extends StatelessWidget {
  const WeekDatePicker({
    super.key,
    required this.days,
    required this.selectedDate,
    required this.dailyTargets,
    required this.userAllergies,
    required this.onSelected,
  });

  final List<MealPlanDay> days;
  final DateTime selectedDate;
  final Nutrition dailyTargets;
  final List<String> userAllergies;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return Row(
      children: [
        for (final day in days)
          Expanded(
            child: _DayPill(
              day: day,
              selected: isSameDay(day.date, selectedDate),
              isToday: isSameDay(day.date, today),
              target: dailyTargets.calories,
              hasConflict: day.conflictCount(userAllergies) > 0,
              onTap: () => onSelected(day.date),
            ),
          ),
      ],
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.target,
    required this.hasConflict,
    required this.onTap,
  });

  final MealPlanDay day;
  final bool selected;
  final bool isToday;
  final int target;
  final bool hasConflict;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final vl = context.vl;
    final kcal = day.totals.calories;
    final ratio = target == 0 ? 0.0 : kcal / target;
    final fg = selected ? cs.onPrimary : cs.onSurface;

    final Color dotColor;
    final bool hollow;
    if (hasConflict || ratio > 1.1) {
      dotColor = selected ? cs.onPrimary : vl.caution;
      hollow = false;
    } else if (ratio >= 0.9) {
      dotColor = selected ? cs.onPrimary : vl.success;
      hollow = false;
    } else {
      dotColor = selected ? cs.onPrimary : vl.muted;
      hollow = true;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        button: true,
        selected: selected,
        label: '${formatLongDate(day.date)}, ${formatInt(kcal)} kcal'
            '${hasConflict ? ', có món cần kiểm tra dị ứng' : ''}',
        excludeSemantics: true,
        child: Material(
          color: selected ? cs.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 68,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    weekdayShort(day.date),
                    style: context.textStyles.labelSmall?.copyWith(
                      color: selected ? cs.onPrimary : vl.muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day.date.day}',
                    style: AppTypography.mono(
                        size: 16, weight: FontWeight.w700, color: fg),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hollow ? Colors.transparent : dotColor,
                      border: Border.all(color: dotColor, width: 1.5),
                    ),
                  ),
                  if (isToday && !selected)
                    Container(
                      margin: const EdgeInsets.only(top: 3),
                      width: 14,
                      height: 2,
                      color: cs.primary,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
