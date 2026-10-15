// lib/features/meal_planner/presentation/screens/meal_planner_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/vl_colors.dart';
import '../../../../core/utils/labels.dart';
import '../../../../core/widgets/account_button.dart';
import '../../../../core/widgets/floating_bar_clearance.dart';
import '../../../../core/widgets/guest_gate.dart';
import '../../../../core/widgets/state_views.dart';
import '../../../../core/widgets/vl_card.dart';
import '../../../recipe/presentation/screens/recipe_detail_screen.dart';
import '../../domain/entities/meal_plan.dart';
import '../controllers/meal_plan_controller.dart';
import '../widgets/allergy_guard_banner.dart';
import '../widgets/health_header_card.dart';
import '../widgets/macro_progress_bar.dart';
import '../widgets/meal_picker_sheet.dart';
import '../widgets/meal_planner_skeleton.dart';
import '../widgets/meal_slot_card.dart';
import '../widgets/pantry_section.dart';
import '../widgets/week_date_picker.dart';
import 'health_profile_edit_screen.dart';

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

enum _PlanAction { regenerate, fromPantry, manual }

class _Loaded extends ConsumerWidget {
  const _Loaded({required this.state});

  final MealPlannerState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = state.plan;
    final day = state.selectedDay;
    final allergies = state.profile.allergies;
    final controller = ref.read(mealPlanControllerProvider.notifier);

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
          SliverAppBar.medium(
            title: const Text('Thực đơn AI'),
            actions: [
              PopupMenuButton<_PlanAction>(
                tooltip: 'Tuỳ chọn thực đơn',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (action) => switch (action) {
                  _PlanAction.regenerate =>
                    _replaceWeek(context, ref, fromPantry: false),
                  _PlanAction.fromPantry =>
                    _replaceWeek(context, ref, fromPantry: true),
                  _PlanAction.manual => _startManual(context, ref),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _PlanAction.regenerate,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.auto_awesome),
                      title: Text('Tạo lại bằng AI'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _PlanAction.fromPantry,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.kitchen_outlined),
                      title: Text('Tạo thực đơn từ tủ lạnh'),
                    ),
                  ),
                  PopupMenuItem(
                    value: _PlanAction.manual,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_calendar_outlined),
                      title: Text('Tự lên thực đơn'),
                    ),
                  ),
                ],
              ),
              const AccountButton(),
            ],
          ),
          SliverPadding(
            padding:
                EdgeInsets.fromLTRB(16, 4, 16, floatingBarClearance(context)),
            sliver: SliverList.list(
              children: [
                HealthHeaderCard(
                  profile: state.profile,
                  onEdit: () => Navigator.of(context)
                      .push(HealthProfileEditScreen.route()),
                ),
                const SizedBox(height: 16),
                if (plan == null || day == null)
                  VLCard(
                    child: Column(
                      children: [
                        EmptyStateView(
                          icon: Icons.auto_awesome,
                          title: 'Chưa có thực đơn tuần này',
                          message:
                              'AI sẽ tạo 7 ngày thực đơn thuần chay phù hợp mục tiêu "${state.profile.goal.label}" và loại trừ món bạn dị ứng.',
                          actionLabel: 'Tạo thực đơn',
                          onAction: controller.generatePlan,
                        ),
                        TextButton.icon(
                          onPressed: controller.createEmptyPlan,
                          icon: const Icon(Icons.edit_calendar_outlined),
                          label: const Text('Tự lên thực đơn'),
                        ),
                      ],
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
                    targets: plan.dailyTargets,
                    estimated: day.estimatedMacros,
                    estimatedDishes: [
                      for (final r in day.mealsWithEstimates) r.name
                    ],
                  ),
                  const SizedBox(height: 12),
                  AllergyGuardBanner(
                      allergies: allergies,
                      conflictCount: day.conflictCount(allergies)),
                  const SizedBox(height: 12),
                  for (final slot in MealSlot.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: switch (day.meals[slot]) {
                        final recipe? => MealSlotCard(
                            slot: slot,
                            recipe: recipe,
                            userAllergies: allergies,
                            isSwapping: state.swappingSlot == slot,
                            onOpen: recipe.hasDetail
                                ? () => Navigator.of(context).push(
                                    RecipeDetailScreen.route(recipe.id,
                                        name: recipe.name))
                                : null,
                            onSwap: () => _pick(context, ref, slot, recipe),
                            onSeasonalSwap: recipe.seasonalSwap == null
                                ? null
                                : () => _run(context, ref, slot, recipe,
                                    seasonal: true),
                          ),
                        null => EmptyMealSlotCard(
                            slot: slot,
                            busy: state.swappingSlot == slot,
                            onAdd: () => _pick(context, ref, slot, null),
                          ),
                      },
                    ),
                ],
                const SizedBox(height: 4),
                PantrySection(
                  onGenerate: () => _replaceWeek(context, ref,
                      fromPantry: true, ask: plan != null),
                ),
                const SizedBox(height: 12),
                Text(
                  'Thông tin chỉ mang tính tham khảo, không thay thế tư vấn y tế.',
                  textAlign: TextAlign.center,
                  style: context.textStyles.bodySmall
                      ?.copyWith(color: context.vl.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Tạo lại bằng AI" / "Tạo thực đơn từ tủ lạnh": confirms before
  /// replacing a week the member may have edited.
  Future<void> _replaceWeek(BuildContext context, WidgetRef ref,
      {required bool fromPantry, bool ask = true}) async {
    final notifier = ref.read(mealPlanControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    if (ask && state.plan != null) {
      final ok = await _confirm(
        context,
        title: fromPantry
            ? 'Tạo lại cả tuần từ tủ lạnh?'
            : 'Tạo lại thực đơn cả tuần?',
        message: 'Các món bạn đã chọn trong tuần sẽ được thay thế.',
        action: 'Tạo lại',
      );
      if (!ok) return;
    }
    final generated = await notifier.generatePlan(fromPantry: fromPantry);
    if (fromPantry && generated) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Đã tạo thực đơn ưu tiên nguyên liệu trong tủ.')));
    }
  }

  Future<void> _startManual(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(mealPlanControllerProvider.notifier);
    if (state.plan != null &&
        !await _confirm(
          context,
          title: 'Tự lên thực đơn?',
          message:
              'Cả tuần sẽ trống để bạn tự chọn từng bữa từ AI, công thức của bạn, chuyên gia hoặc tự nhập.',
          action: 'Bắt đầu',
        )) {
      return;
    }
    await notifier.createEmptyPlan();
  }

  static Future<bool> _confirm(BuildContext context,
      {required String title,
      required String message,
      required String action}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Fill or replace [slot] from one of the 4 sources.
  Future<void> _pick(BuildContext context, WidgetRef ref, MealSlot slot,
      Recipe? current) async {
    final pick = await MealPickerSheet.show(context,
        slot: slot, allergies: state.profile.allergies, current: current);
    if (pick == null || !context.mounted) return;
    switch (pick) {
      case RecipePick(:final recipe):
        await _run(context, ref, slot, recipe);
      case ManualPick():
        await _addManual(context, ref, slot, pick);
      case RemovePick():
        await _remove(context, ref, slot);
    }
  }

  Future<void> _addManual(BuildContext context, WidgetRef ref, MealSlot slot,
      ManualPick pick) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(mealPlanControllerProvider.notifier);
    try {
      final added = await notifier.addManualMeal(
        slot: slot,
        name: pick.name,
        calories: pick.calories,
        proteinG: pick.proteinG,
        carbsG: pick.carbsG,
        fatG: pick.fatG,
      );
      final warning = added.allergenConflicts.isEmpty
          ? ''
          : ' Lưu ý: món có thể chứa '
              '${added.allergenConflicts.map(allergenLabel).join(', ').toLowerCase()}.';
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
              'Đã thêm "${pick.name}" vào ${slot.label.toLowerCase()}.$warning'),
          action: SnackBarAction(
            label: 'Hoàn tác',
            onPressed: () => notifier.undoAddMeal(added).catchError((Object e) {
              messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
            }),
          ),
        ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Chưa thêm được món. ${describeError(e)}')));
    }
  }

  Future<void> _remove(
      BuildContext context, WidgetRef ref, MealSlot slot) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(mealPlanControllerProvider.notifier);
    try {
      final removed = await notifier.removeMeal(slot);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          duration: const Duration(seconds: 5),
          content: Text('Đã bỏ món khỏi ${slot.label.toLowerCase()}'),
          action: removed == null
              ? null
              : SnackBarAction(
                  label: 'Hoàn tác',
                  onPressed: () {
                    notifier.swapMeal(slot, removed).catchError((Object e) {
                      messenger.showSnackBar(
                          SnackBar(content: Text(describeError(e))));
                      return null;
                    });
                  },
                ),
        ));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('Chưa bỏ được món. ${describeError(e)}')));
    }
  }

  /// Performs the swap and offers Undo for 5 s.
  Future<void> _run(
      BuildContext context, WidgetRef ref, MealSlot slot, Recipe recipe,
      {bool seasonal = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(mealPlanControllerProvider.notifier);
    final wasEmpty = state.selectedDay?.meals[slot] == null;
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
            content: Text(wasEmpty
                ? 'Đã thêm $newName vào ${slot.label.toLowerCase()}'
                : 'Đã đổi ${slot.label.toLowerCase()} sang $newName'),
            action: SnackBarAction(
              label: 'Hoàn tác',
              onPressed: () {
                final undo = previous == null
                    ? notifier.removeMeal(slot)
                    : notifier.swapMeal(slot, previous);
                undo.catchError((Object e) {
                  messenger
                      .showSnackBar(SnackBar(content: Text(describeError(e))));
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
