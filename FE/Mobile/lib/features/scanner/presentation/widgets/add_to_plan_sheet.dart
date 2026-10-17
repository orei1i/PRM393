// lib/features/scanner/presentation/widgets/add_to_plan_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../meal_planner/domain/allergy_match.dart';
import '../../../meal_planner/domain/entities/meal_plan.dart';
import '../../../meal_planner/presentation/controllers/meal_plan_controller.dart';
import '../../domain/entities/detected_ingredient.dart';
import 'confirm_ingredient_sheet.dart';

/// "Thêm vào thực đơn": pick which meal of today the AI suggestion replaces
/// (today's meals: the member's pattern plus any extra meal of the day).
/// Pops the chosen [MealSlot]. Warns (like the planner) when the dish contains
/// one of the user's allergens.
class AddToPlanSheet extends ConsumerStatefulWidget {
  const AddToPlanSheet({super.key, required this.suggestion});

  final MenuSuggestion suggestion;

  static Future<MealSlot?> show(
      BuildContext context, MenuSuggestion suggestion) {
    return showModalBottomSheet<MealSlot>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddToPlanSheet(suggestion: suggestion),
    );
  }

  @override
  ConsumerState<AddToPlanSheet> createState() => _AddToPlanSheetState();
}

class _AddToPlanSheetState extends ConsumerState<AddToPlanSheet> {
  // Pre-select the next meal of the day.
  late MealSlot _slot = switch (DateTime.now().hour) {
    < 10 => MealSlot.breakfast,
    < 15 => MealSlot.lunch,
    _ => MealSlot.dinner,
  };

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final m = widget.suggestion;
    final planner = ref.watch(mealPlanControllerProvider);
    final s = planner.valueOrNull;
    final today = s?.plan?.dayFor(dateOnly(DateTime.now()));
    final conflicts = s == null
        ? const <String>[]
        : allergyConflicts(
            tags: m.allergens,
            texts: [m.name, ...m.usedIngredients, ...m.missingIngredients],
            userAllergies: s.profile.allergies);
    final slots = s == null
        ? MealPattern.standard
        : today == null
            ? s.pattern
            : s.slotsFor(today);
    final selected = slots.contains(_slot) ? _slot : slots.first;

    String currentMeal(MealSlot slot) {
      if (s == null) {
        return planner.hasError ? 'Chưa tải được thực đơn' : 'Đang tải…';
      }
      final recipe = today?.meals[slot];
      return recipe == null ? 'Chưa có món' : 'Thay cho: ${recipe.name}';
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 20 + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Thêm vào thực đơn hôm nay',
              style: context.textStyles.titleLarge),
          const SizedBox(height: 6),
          Text(
            '${m.name} · ${formatInt(m.calories)} kcal',
            style: context.textStyles.bodyMedium?.copyWith(color: vl.muted),
          ),
          const SizedBox(height: 16),
          for (final slot in slots)
            OptionTile(
              label: slot.label,
              subtitle: currentMeal(slot),
              selected: selected == slot,
              onTap: () => setState(() => _slot = slot),
            ),
          if (conflicts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Semantics(
              liveRegion: true,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: vl.cautionContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: vl.cautionBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 18, color: vl.onCautionContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Món này có thể chứa chất bạn dị ứng '
                        '(${conflicts.map(allergenLabel).join(', ')}). '
                        'Hãy kiểm tra kỹ trước khi nấu.',
                        style: context.textStyles.bodySmall?.copyWith(
                          color: vl.onCautionContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(selected),
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(
              '${conflicts.isEmpty ? 'Thêm' : 'Vẫn thêm'} vào ${selected.label.toLowerCase()}',
            ),
          ),
        ],
      ),
    );
  }
}
