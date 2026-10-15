// lib/features/meal_planner/presentation/screens/meal_planner_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/widgets/account_button.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../domain/entities/meal_plan.dart';
import '../controllers/meal_plan_controller.dart';
import '../widgets/allergy_guard_banner.dart';
import '../widgets/health_header_card.dart';
import '../widgets/macro_progress_bar.dart';
import '../widgets/meal_planner_skeleton.dart';
import '../widgets/meal_slot_card.dart';
import '../widgets/swap_meal_sheet.dart';
import '../widgets/week_date_picker.dart';

class MealPlannerScreen extends StatelessWidget {
  const MealPlannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: GuestGate(
        icon: Icons.calendar_month_rounded,
        title: 'Thực đơn 7 ngày của riêng bạn',
        message:
            'Đăng nhập để AI lên thực đơn theo chiều cao, cân nặng, mục tiêu và dị ứng của bạn.',
        benefits: [
          'Thực đơn thuần chay 7 ngày, đổi món chỉ với 1 chạm',
          'Theo dõi đạm, tinh bột, chất béo, chất xơ mỗi ngày',
          'Tự động loại trừ món chứa chất bạn dị ứng',
        ],
        child: _MealPlannerBody(),
      ),
    );
  }
}

class _MealPlannerBody extends ConsumerWidget {
  const _MealPlannerBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(mealPlanControllerProvider);

    // A failed refresh keeps the old plan on screen; tell the user why it didn't update.
    ref.listen(mealPlanControllerProvider, (previous, next) {
      if (next is AsyncError<MealPlannerState> && next.hasValue) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Chưa cập nhật được. ${describeError(next.error)}')),
        );
      }
    });

    return switch (async) {
      AsyncData(:final value) => _Loaded(state: value),
      AsyncError(:final error) when !async.hasValue => SafeArea(
          child: Center(
            child: ErrorStateView(
              error: error,
              onRetry: () => ref.invalidate(mealPlanControllerProvider),
            ),
          ),
        ),
      _ when async.hasValue => _Loaded(state: async.requireValue),
      _ => const MealPlannerSkeleton(),
    };
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.state});

  final MealPlannerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(mealPlanControllerProvider.notifier);
    final plan = state.plan;
    final day = state.selectedDay;
    final allergies = state.profile.allergies;

    return RefreshIndicator(
      onRefresh: () async {
        try {
          ref.invalidate(mealPlanControllerProvider);
          await ref.read(mealPlanControllerProvider.future);
        } catch (_) {
          // Surfaced by the ref.listen above.
        }
      },
      child: CustomScrollView(
        slivers: [
          const SliverAppBar.medium(
            title: Text('Thực đơn AI'),
            actions: [AccountButton()],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            sliver: SliverList.list(
              children: [
                HealthHeaderCard(profile: state.profile),
                const SizedBox(height: 16),
                if (plan == null || day == null)
                  VLCard(
                    child: EmptyStateView(
                      icon: Icons.auto_awesome,
                      title: 'Chưa có thực đơn tuần này',
                      message:
                          'AI sẽ tạo 7 ngày thực đơn thuần chay phù hợp mục tiêu "${state.profile.goal.label}" và loại trừ món bạn dị ứng.',
                      actionLabel: 'Tạo thực đơn',
                      onAction: controller.generatePlan,
                    ),
                  )
                else ...[
                  WeekDatePicker(
                    days: plan.days,
                    selectedDate: state.selectedDate,
                    dailyTargets: plan.dailyTargets,
                    userAllergies: allergies,
                    onSelected: controller.selectDate,
                  ),
                  const SizedBox(height: 12),
                  DailyMacroCard(
                      date: day.date,
                      totals: day.totals,
                      targets: plan.dailyTargets),
                  const SizedBox(height: 12),
                  AllergyGuardBanner(
                      allergies: allergies,
                      conflictCount: day.conflictCount(allergies)),
                  const SizedBox(height: 12),
                  for (final slot in MealSlot.values)
                    if (day.meals[slot] case final recipe?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: MealSlotCard(
                          slot: slot,
                          recipe: recipe,
                          userAllergies: allergies,
                          isSwapping: state.swappingSlot == slot,
                          onSwap: () =>
                              _openSwapSheet(context, ref, slot, recipe),
                          onSeasonalSwap: recipe.seasonalSwap == null
                              ? null
                              : () => _run(context, ref, slot, recipe,
                                  seasonal: true),
                        ),
                      ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Thông tin chỉ mang tính tham khảo, không thay thế tư vấn y tế.',
                      textAlign: TextAlign.center,
                      style: context.textStyles.bodySmall
                          ?.copyWith(color: context.vl.muted),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSwapSheet(BuildContext context, WidgetRef ref,
      MealSlot slot, Recipe current) async {
    final picked =
        await SwapMealSheet.show(context, slot: slot, current: current);
    if (picked == null || !context.mounted) return;
    await _run(context, ref, slot, picked);
  }

  /// Performs the swap and offers Undo for 5 s.
  Future<void> _run(
      BuildContext context, WidgetRef ref, MealSlot slot, Recipe recipe,
      {bool seasonal = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(mealPlanControllerProvider.notifier);
    try {
      final previous = seasonal
          ? await notifier.swapToSeasonal(slot)
          : await notifier.swapMeal(slot, recipe);
      final newName = seasonal
          ? 'món ${recipe.seasonalSwap?.ingredient ?? 'đang mùa'}'
          : recipe.name;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text('Đã đổi ${slot.label.toLowerCase()} sang $newName'),
            action: previous == null
                ? null
                : SnackBarAction(
                    label: 'Hoàn tác',
                    onPressed: () {
                      notifier.swapMeal(slot, previous).catchError((Object e) {
                        messenger.showSnackBar(
                            SnackBar(content: Text(describeError(e))));
                        return null;
                      });
                    },
                  ),
          ),
        );
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Chưa đổi được món. ${describeError(e)}')));
    }
  }
}
