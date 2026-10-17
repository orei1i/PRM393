// lib/features/meal_planner/presentation/widgets/meal_slot_card.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/meal_plan.dart';

/// Icon for a meal of the day.
IconData mealSlotIcon(MealSlot slot) => switch (slot) {
      MealSlot.breakfast => Icons.wb_twilight_rounded,
      MealSlot.snackAm => Icons.coffee_outlined,
      MealSlot.lunch => Icons.wb_sunny_outlined,
      MealSlot.snackPm => Icons.cookie_outlined,
      MealSlot.dinner => Icons.nightlight_outlined,
      MealSlot.snackLate => Icons.bedtime_outlined,
    };

/// One meal slot: recipe, calories/macros, source badge, allergy chips,
/// seasonal swap, swap action. [onOpen] opens the recipe. An [extra] slot
/// (added to this day only) is marked "Bữa thêm" and offers [onRemove].
class MealSlotCard extends StatelessWidget {
  const MealSlotCard({
    super.key,
    required this.slot,
    required this.recipe,
    required this.userAllergies,
    required this.isSwapping,
    required this.onSwap,
    this.onSeasonalSwap,
    this.onOpen,
    this.extra = false,
    this.onRemove,
  });

  final MealSlot slot;
  final Recipe recipe;
  final List<String> userAllergies;
  final bool isSwapping;
  final VoidCallback onSwap;
  final VoidCallback? onSeasonalSwap;
  final VoidCallback? onOpen;
  final bool extra;

  /// "Bỏ món" on an extra slot: the slot disappears with its dish.
  final VoidCallback? onRemove;

  IconData get _slotIcon => mealSlotIcon(slot);

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final n = recipe.nutrition;
    final conflicts = recipe.allergenConflicts(userAllergies);
    final seasonal = recipe.seasonalSwap;

    return VLCard(
      padding: EdgeInsets.zero,
      borderColor: conflicts.isNotEmpty ? vl.cautionBorder : null,
      onTap: onOpen,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Thumbnail(icon: _slotIcon, imageUrl: recipe.imageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: extra
                                  ? '${slot.label} (bữa thêm) · '
                                  : '${slot.label} · ',
                              style: context.textStyles.bodySmall
                                  ?.copyWith(color: vl.muted)),
                          TextSpan(
                              text: recipe.hasNutrition
                                  ? '${formatInt(n.calories)} kcal'
                                  : 'Chưa rõ kcal',
                              style: AppTypography.mono(
                                  size: 12,
                                  weight: FontWeight.w600,
                                  color: vl.muted)),
                        ]),
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: Text(
                          recipe.name,
                          key: ValueKey(recipe.id),
                          style: context.textStyles.titleSmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Only the macros the dish really has: a typed-in dish
                      // with just "Đạm" shows just "Đạm".
                      if (n.summary() != null ||
                          recipe.prepMinutes != null ||
                          recipe.portionLabel != null)
                        Text(
                          [
                            if (recipe.portionLabel case final portion?)
                              portion,
                            if (n.summary() case final macros?) macros,
                            if (recipe.prepMinutes != null)
                              '${recipe.prepMinutes} phút',
                          ].join(' · '),
                          style: context.textStyles.bodySmall
                              ?.copyWith(color: vl.muted),
                        ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          MealSourceBadge(recipe: recipe),
                          for (final a in conflicts)
                            VLTag.caution(context,
                                'Chứa ${allergenLabel(a).toLowerCase()}'),
                          for (final t in recipe.dietTags.take(2))
                            VLTag.neutral(context, dietTagLabel(t)),
                          if (seasonal != null && onSeasonalSwap != null)
                            _SeasonalChip(
                              label: 'Đổi sang ${seasonal.ingredient} đang mùa',
                              onTap: isSwapping ? null : onSeasonalSwap,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Đổi ${slot.label.toLowerCase()}',
                      onPressed: isSwapping ? null : onSwap,
                      style:
                          IconButton.styleFrom(minimumSize: const Size(44, 44)),
                      icon: const Icon(Icons.swap_horiz_rounded),
                    ),
                    if (onRemove != null)
                      IconButton(
                        tooltip: 'Bỏ món ${slot.label.toLowerCase()}',
                        onPressed: isSwapping ? null : onRemove,
                        style: IconButton.styleFrom(
                            minimumSize: const Size(44, 44)),
                        icon: Icon(Icons.remove_circle_outline_rounded,
                            color: vl.muted),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (isSwapping)
            LinearProgressIndicator(
              minHeight: 3,
              color: vl.ai,
              backgroundColor: vl.aiContainer,
              semanticsLabel: 'Đang đổi món',
            ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.icon, this.imageUrl});

  final IconData icon;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: context.colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: context.colors.primary),
    );
    if (imageUrl == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        imageUrl!,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

class _SeasonalChip extends StatelessWidget {
  const _SeasonalChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return Material(
      color: vl.successContainer,
      shape: StadiumBorder(
          side: BorderSide(color: vl.success.withValues(alpha: 0.35))),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.eco_outlined, size: 14, color: vl.onSuccessContainer),
              const SizedBox(width: 4),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: context.textStyles.labelMedium
                        ?.copyWith(color: vl.onSuccessContainer)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the dish came from: AI, typed in, own recipe, a chef, the fridge.
class MealSourceBadge extends StatelessWidget {
  const MealSourceBadge({super.key, required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final cs = context.colors;
    final (IconData icon, String label, Color bg, Color fg) =
        switch (recipe.source) {
      MealSource.ai => (
          Icons.auto_awesome,
          MealSource.ai.label,
          vl.aiContainer,
          vl.onAiContainer
        ),
      MealSource.chef => (
          Icons.verified_outlined,
          recipe.sourceName == null
              ? 'Chuyên gia đề xuất'
              : 'Chuyên gia · ${recipe.sourceName}',
          vl.successContainer,
          vl.onSuccessContainer
        ),
      MealSource.userRecipe => (
          Icons.menu_book_outlined,
          MealSource.userRecipe.label,
          cs.secondaryContainer,
          cs.onSecondaryContainer
        ),
      MealSource.manual => (
          Icons.edit_note_rounded,
          MealSource.manual.label,
          cs.surfaceContainer,
          cs.onSurfaceVariant
        ),
      MealSource.fridgeScan => (
          Icons.kitchen_outlined,
          MealSource.fridgeScan.label,
          cs.surfaceContainer,
          cs.onSurfaceVariant
        ),
    };
    // Like VLTag, but the label shrinks (ellipsis) on narrow cards and at
    // large text sizes instead of overflowing.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: context.textStyles.labelMedium?.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}

/// A slot with no dish yet (a plan built by hand): "Thêm món".
class EmptyMealSlotCard extends StatelessWidget {
  const EmptyMealSlotCard(
      {super.key, required this.slot, required this.onAdd, this.busy = false});

  final MealSlot slot;
  final VoidCallback onAdd;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return VLCard(
      onTap: busy ? null : onAdd,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              border: Border.all(color: vl.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.add_rounded, color: vl.muted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slot.label,
                    style: context.textStyles.bodySmall
                        ?.copyWith(color: vl.muted)),
                Text('Chưa có món', style: context.textStyles.titleSmall),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton.filledTonal(
              tooltip: 'Thêm ${slot.label.toLowerCase()}',
              onPressed: onAdd,
              style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
    );
  }
}
