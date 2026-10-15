// lib/features/meal_planner/presentation/controllers/meal_plan_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../data/meal_planner_api_service.dart';
import '../../data/models/health_profile_model.dart';
import '../../data/models/meal_plan_model.dart';
import '../../domain/entities/health_profile.dart';
import '../../domain/entities/meal_plan.dart';

class MealPlannerState {
  const MealPlannerState({
    required this.profile,
    required this.plan,
    required this.selectedDate,
    this.swappingSlot,
  });

  final HealthProfile profile;

  /// `null` → user has no plan for this week yet (empty state).
  final MealPlan? plan;
  final DateTime selectedDate;

  /// Slot currently being replaced (shows inline progress on that card).
  final MealSlot? swappingSlot;

  MealPlanDay? get selectedDay => plan?.dayFor(selectedDate);

  MealPlannerState copyWith({
    HealthProfile? profile,
    MealPlan? plan,
    DateTime? selectedDate,
    MealSlot? swappingSlot,
    bool clearSwapping = false,
  }) {
    return MealPlannerState(
      profile: profile ?? this.profile,
      plan: plan ?? this.plan,
      selectedDate: selectedDate ?? this.selectedDate,
      swappingSlot: clearSwapping ? null : (swappingSlot ?? this.swappingSlot),
    );
  }
}

final mealPlanControllerProvider =
    AsyncNotifierProvider<MealPlanController, MealPlannerState>(
        MealPlanController.new);

class MealPlanController extends AsyncNotifier<MealPlannerState> {
  MealPlannerApiService get _api => ref.read(mealPlannerApiProvider);

  @override
  Future<MealPlannerState> build() async {
    final api = ref.watch(mealPlannerApiProvider);
    final results = await Future.wait<Object?>([
      api.getHealthProfile(),
      api.getCurrentMealPlan(),
    ]);
    final profile = (results[0]! as HealthProfileDto).toEntity();
    final plan = (results[1] as MealPlanDto?)?.toEntity();
    return MealPlannerState(
      profile: profile,
      plan: plan,
      selectedDate: _initialDate(plan),
    );
  }

  // ---------------------------------------------------------------- actions --

  void selectDate(DateTime date) {
    final current = state;
    if (!current.hasValue) return;
    state =
        AsyncData(current.requireValue.copyWith(selectedDate: dateOnly(date)));
  }

  /// Empty state → "Tạo thực đơn". Keeps the profile visible while generating.
  Future<void> generatePlan() async {
    final previous = state.requireValue;
    state = const AsyncLoading<MealPlannerState>();
    state = await AsyncValue.guard(() async {
      final dto =
          await _api.generateMealPlan(startDate: startOfWeek(DateTime.now()));
      final plan = dto.toEntity();
      return previous.copyWith(plan: plan, selectedDate: _initialDate(plan));
    });
  }

  /// AI alternatives for the selected day's [slot]. Filters allergens again on
  /// the client as defence in depth (the server already should).
  Future<List<Recipe>> fetchSwapSuggestions(MealSlot slot) async {
    final s = state.requireValue;
    final plan = s.plan;
    if (plan == null) return const [];
    final dtos = await _api.getSwapSuggestions(
        planId: plan.id, date: s.selectedDate, slot: slot);
    return dtos
        .map((d) => d.toEntity())
        .where((r) => r.allergenConflicts(s.profile.allergies).isEmpty)
        .toList();
  }

  /// Optimistic swap with rollback. Returns the replaced recipe (for Undo).
  Future<Recipe?> swapMeal(MealSlot slot, Recipe replacement) async {
    final s = state.requireValue;
    final plan = s.plan;
    final day = s.selectedDay;
    if (plan == null || day == null) return null;
    final previous = day.meals[slot];

    state = AsyncData(s.copyWith(
      plan: plan.replaceDay(day.replaceMeal(slot, replacement)),
      swappingSlot: slot,
    ));

    try {
      final serverDay = await _api.swapMeal(
        planId: plan.id,
        request: SwapMealRequestDto(
            date: day.date, slot: slot, recipeId: replacement.id),
      );
      _applyServerDay(serverDay.toEntity());
      return previous;
    } catch (_) {
      _applyServerDay(day); // rollback to the untouched day
      rethrow;
    }
  }

  /// 1-tap seasonal swap (server resolves the recipe by id).
  Future<Recipe?> swapToSeasonal(MealSlot slot) async {
    final s = state.requireValue;
    final plan = s.plan;
    final day = s.selectedDay;
    final seasonal = day?.meals[slot]?.seasonalSwap;
    if (plan == null || day == null || seasonal == null) return null;
    final previous = day.meals[slot];

    state = AsyncData(s.copyWith(swappingSlot: slot));
    try {
      final serverDay = await _api.swapMeal(
        planId: plan.id,
        request: SwapMealRequestDto(
            date: day.date, slot: slot, recipeId: seasonal.recipeId),
      );
      _applyServerDay(serverDay.toEntity());
      return previous;
    } catch (_) {
      _applyServerDay(day);
      rethrow;
    }
  }

  // ---------------------------------------------------------------- helpers --

  void _applyServerDay(MealPlanDay day) {
    final latest = state.requireValue;
    final plan = latest.plan;
    if (plan == null) return;
    state = AsyncData(
        latest.copyWith(plan: plan.replaceDay(day), clearSwapping: true));
  }

  static DateTime _initialDate(MealPlan? plan) {
    final today = dateOnly(DateTime.now());
    if (plan == null || plan.days.isEmpty) return today;
    return plan.dayFor(today) != null ? today : plan.days.first.date;
  }
}
