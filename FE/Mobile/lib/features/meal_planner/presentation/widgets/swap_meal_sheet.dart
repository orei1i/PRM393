// lib/features/meal_planner/presentation/widgets/swap_meal_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/shimmer.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/meal_plan.dart';
import '../controllers/meal_plan_controller.dart';

/// Bottom sheet with AI swap suggestions. Pops with the chosen [Recipe].
class SwapMealSheet extends ConsumerStatefulWidget {
  const SwapMealSheet({super.key, required this.slot, required this.current});

  final MealSlot slot;
  final Recipe current;

  static Future<Recipe?> show(BuildContext context, {required MealSlot slot, required Recipe current}) {
    return showModalBottomSheet<Recipe>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SwapMealSheet(slot: slot, current: current),
    );
  }

  @override
  ConsumerState<SwapMealSheet> createState() => _SwapMealSheetState();
}

class _SwapMealSheetState extends ConsumerState<SwapMealSheet> {
  late Future<List<Recipe>> _suggestions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _suggestions = ref.read(mealPlanControllerProvider.notifier).fetchSwapSuggestions(widget.slot);
  }

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Đổi ${widget.slot.label.toLowerCase()}', style: context.textStyles.titleLarge)),
              const AiBadge(label: 'AI gợi ý'),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Cùng mức năng lượng (±10%) với "${widget.current.name}" và an toàn với dị ứng của bạn.',
            style: context.textStyles.bodyMedium?.copyWith(color: vl.muted),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<Recipe>>(
            future: _suggestions,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _SuggestionSkeleton();
              }
              if (snapshot.hasError) {
                return ErrorStateView(
                  error: snapshot.error!,
                  onRetry: () => setState(_load),
                );
              }
              final items = snapshot.data ?? const <Recipe>[];
              if (items.isEmpty) {
                return const EmptyStateView(
                  icon: Icons.search_off_rounded,
                  title: 'Chưa có món thay thế phù hợp',
                  message: 'Không tìm được món cùng mức năng lượng mà tránh được dị ứng của bạn. Thử lại vào lúc khác nhé.',
                );
              }
              return Column(
                children: [
                  for (final r in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SuggestionTile(
                        recipe: r,
                        kcalDelta: r.nutrition.calories - widget.current.nutrition.calories,
                        onTap: () => Navigator.of(context).pop(r),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.recipe, required this.kcalDelta, required this.onTap});

  final Recipe recipe;
  final int kcalDelta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vl = context.vl;
    final n = recipe.nutrition;
    final delta = kcalDelta == 0 ? '±0' : (kcalDelta > 0 ? '+$kcalDelta' : '$kcalDelta');

    return VLCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(recipe.name, style: context.textStyles.titleSmall),
                const SizedBox(height: 4),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${formatInt(n.calories)} kcal ', style: AppTypography.mono(size: 12, color: context.colors.onSurface)),
                  TextSpan(text: '($delta)', style: AppTypography.mono(size: 12, weight: FontWeight.w500, color: vl.muted)),
                  TextSpan(text: ' · Đạm ${n.proteinG.round()} g', style: context.textStyles.bodySmall?.copyWith(color: vl.muted)),
                ])),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    VLTag(
                      label: 'An toàn dị ứng',
                      icon: Icons.verified_user_outlined,
                      background: vl.successContainer,
                      foreground: vl.onSuccessContainer,
                    ),
                    for (final t in recipe.dietTags.take(2)) VLTag.neutral(context, dietTagLabel(t)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: vl.muted),
        ],
      ),
    );
  }
}

class _SuggestionSkeleton extends StatelessWidget {
  const _SuggestionSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: Column(
        children: List.generate(
          3,
          (_) => const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: _SkeletonTile(),
          ),
        ),
      ),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: context.vl.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 200, height: 16),
          SizedBox(height: 8),
          SkeletonBox(width: 140, height: 12),
          SizedBox(height: 10),
          SkeletonBox(width: 100, height: 22, radius: 999),
        ],
      ),
    );
  }
}
