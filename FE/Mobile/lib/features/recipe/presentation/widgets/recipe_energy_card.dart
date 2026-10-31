// lib/features/recipe/presentation/widgets/recipe_energy_card.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session/session_controller.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/sign_in_sheet.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../meal_planner/domain/entities/meal_slot.dart';
import '../../../meal_planner/presentation/controllers/meal_plan_controller.dart';
import '../../../meal_planner/presentation/screens/health_profile_edit_screen.dart';
import '../../domain/recipe_customization.dart';
import '../controllers/recipe_customization_controller.dart';

/// "Năng lượng" / "Năng lượng (ước tính)": energy per serving (and its
/// change from the original), the total for the servings cooked, macros,
/// warnings when the change is large or partly unknown, and how one
/// serving fits the member's meal target ("So với mục tiêu").
class RecipeEnergyCard extends ConsumerWidget {
  const RecipeEnergyCard({super.key, required this.custom, this.contextSlot});

  final CustomizedRecipe custom;

  /// The planner slot the page was opened from, if any.
  final MealSlot? contextSlot;

  static String signed(int v) => v == 0
      ? '±0'
      : v > 0
          ? '+${formatInt(v)}'
          : '−${formatInt(v.abs())}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vl = context.vl;
    final energy = custom.energy;
    final modified = energy.modified;
    final estimated = modified || custom.recipe.nutritionEstimated;
    final c0 = energy.original;
    final shown = energy.shown;
    final approx = modified ? '≈ ' : '';
    final total = energy.totalFor(custom.servings);

    final lines = <Widget>[
      Text(estimated ? 'Năng lượng (ước tính)' : 'Năng lượng',
          style: context.textStyles.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      if (c0 == null || shown == null)
        Text('Chưa có số liệu năng lượng',
            style: context.textStyles.bodyMedium?.copyWith(color: vl.muted))
      else ...[
        Text(
          modified
              ? 'Mỗi phần: ≈ ${formatInt(shown)} kcal (gốc ${formatInt(c0)} '
                  'kcal, ${signed(energy.delta!)})'
              : 'Mỗi phần: ${formatInt(shown)} kcal',
          style: context.textStyles.bodyLarge,
        ),
        if (total != null)
          Text('Tổng ${custom.servings} phần: $approx${formatInt(total)} kcal',
              style: context.textStyles.bodyMedium),
      ],
      if (energy.macroLine case final macros?) ...[
        const SizedBox(height: 4),
        Text('$approx$macros',
            style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
      ],
      if (energy.largeChangeWarning case final w1?) ...[
        const SizedBox(height: 10),
        _Banner(text: w1, caution: true),
      ],
      if (energy.unknownWarning case final w3?) ...[
        const SizedBox(height: 10),
        _Banner(text: w3, caution: false),
      ],
      if (c0 != null && energy.exact != null) ...[
        const SizedBox(height: 10),
        _TargetComparison(
            custom: custom, energy: energy.exact!, contextSlot: contextSlot),
      ],
    ];
    return VLCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines,
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.caution});

  final String text;
  final bool caution;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final bg = caution ? vl.cautionContainer : context.colors.surfaceContainer;
    final fg =
        caution ? vl.onCautionContainer : context.colors.onSurfaceVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: caution ? Border.all(color: vl.cautionBorder) : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
              caution
                  ? Icons.warning_amber_rounded
                  : Icons.info_outline_rounded,
              size: 18,
              color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: context.textStyles.bodySmall?.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}

/// "So với mục tiêu: [Bữa …] ▾" + how one serving fits that meal's target;
/// sign-in / profile hints when there is no target to compare with.
class _TargetComparison extends ConsumerWidget {
  const _TargetComparison(
      {required this.custom, required this.energy, this.contextSlot});

  final CustomizedRecipe custom;
  final double energy;
  final MealSlot? contextSlot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vl = context.vl;
    final isGuest =
        ref.watch(sessionControllerProvider.select((s) => s.isGuest));
    if (isGuest) {
      return TextButton.icon(
        onPressed: () => ensureSignedIn(context, ref,
            reason: 'Đăng nhập để so món này với mục tiêu bữa ăn của bạn.'),
        icon: const Icon(Icons.login_rounded),
        label: const Text('Đăng nhập để so với mục tiêu bữa ăn của bạn'),
      );
    }
    final planner = ref.watch(mealPlanControllerProvider).valueOrNull;
    if (planner == null) return const SizedBox.shrink();
    final profile = planner.healthProfile;
    if (profile == null) {
      return TextButton.icon(
        onPressed: () =>
            Navigator.of(context).push(HealthProfileEditScreen.route()),
        icon: const Icon(Icons.monitor_heart_outlined),
        label: const Text('Thiết lập hồ sơ sức khoẻ để so với mục tiêu bữa ăn'),
      );
    }
    final targets = slotTargets(profile);
    if (targets.isEmpty) {
      return Text(
        'Thêm giới tính và năm sinh trong Hồ sơ sức khoẻ để so với mục tiêu '
        'bữa ăn',
        style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
      );
    }
    final picked =
        ref.watch(recipeCustomizationProvider(custom.recipe.id)).compareSlot;
    final slot = picked != null && targets.containsKey(picked)
        ? picked
        : defaultCompareSlot(targets, custom.energy.original,
            contextSlot: contextSlot)!;
    final comparison =
        SlotComparison(slot: slot, target: targets[slot]!, energy: energy);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wraps the picker under the label when both don't fit (narrow
        // phone, large text).
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text('So với mục tiêu:', style: context.textStyles.bodyMedium),
            PopupMenuButton<MealSlot>(
              tooltip: 'Chọn bữa để so',
              initialValue: slot,
              onSelected: ref
                  .read(recipeCustomizationProvider(custom.recipe.id).notifier)
                  .selectCompareSlot,
              itemBuilder: (_) => [
                for (final s in targets.keys)
                  PopupMenuItem(value: s, child: Text(s.label)),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(slot.label,
                          style: context.textStyles.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.colors.primary)),
                    ),
                    Icon(Icons.arrow_drop_down_rounded,
                        color: context.colors.primary),
                  ],
                ),
              ),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              comparison.fits
                  ? Icons.check_circle_outline_rounded
                  : Icons.error_outline_rounded,
              size: 18,
              color: comparison.fits ? vl.success : vl.caution,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(comparison.message,
                  style: context.textStyles.bodyMedium?.copyWith(
                      color: comparison.fits ? vl.success : vl.caution)),
            ),
          ],
        ),
      ],
    );
  }
}
