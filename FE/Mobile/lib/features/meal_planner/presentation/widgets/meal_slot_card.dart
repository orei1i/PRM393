// lib/features/meal_planner/presentation/widgets/meal_slot_card.dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/meal_plan.dart';

/// One meal slot: recipe, calories/macros, allergy chips, seasonal swap, swap action.
class MealSlotCard extends StatelessWidget {
  const MealSlotCard({
    super.key,
    required this.slot,
    required this.recipe,
    required this.userAllergies,
    required this.isSwapping,
    required this.onSwap,
    this.onSeasonalSwap,
  });

  final MealSlot slot;
  final Recipe recipe;
  final List<String> userAllergies;
  final bool isSwapping;
  final VoidCallback onSwap;
  final VoidCallback? onSeasonalSwap;

  IconData get _slotIcon => switch (slot) {
        MealSlot.breakfast => Icons.wb_twilight_rounded,
        MealSlot.lunch => Icons.wb_sunny_outlined,
        MealSlot.dinner => Icons.nightlight_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final n = recipe.nutrition;
    final conflicts = recipe.allergenConflicts(userAllergies);
    final seasonal = recipe.seasonalSwap;

    return VLCard(
      padding: EdgeInsets.zero,
      borderColor: conflicts.isNotEmpty ? vl.cautionBorder : null,
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
                          TextSpan(text: '${slot.label} · ', style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
                          TextSpan(text: '${formatInt(n.calories)} kcal', style: AppTypography.mono(size: 12, weight: FontWeight.w600, color: vl.muted)),
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
                      Text(
                        'Đạm ${n.proteinG.round()} g · Tinh bột ${n.carbsG.round()} g · Béo ${n.fatG.round()} g'
                        '${recipe.prepMinutes == null ? '' : ' · ${recipe.prepMinutes} phút'}',
                        style: context.textStyles.bodySmall?.copyWith(color: vl.muted),
                      ),
                      if (conflicts.isNotEmpty || recipe.dietTags.isNotEmpty || seasonal != null) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final a in conflicts) VLTag.caution(context, 'Chứa ${allergenLabel(a).toLowerCase()}'),
                            for (final t in recipe.dietTags.take(2)) VLTag.neutral(context, dietTagLabel(t)),
                            if (seasonal != null && onSeasonalSwap != null)
                              _SeasonalChip(
                                label: 'Đổi sang ${seasonal.ingredient} đang mùa',
                                onTap: isSwapping ? null : onSeasonalSwap,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filledTonal(
                  tooltip: 'Đổi ${slot.label.toLowerCase()}',
                  onPressed: isSwapping ? null : onSwap,
                  style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                  icon: const Icon(Icons.swap_horiz_rounded),
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
      shape: StadiumBorder(side: BorderSide(color: vl.success.withValues(alpha: 0.35))),
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
              Text(label, style: context.textStyles.labelMedium?.copyWith(color: vl.onSuccessContainer)),
            ],
          ),
        ),
      ),
    );
  }
}
