// lib/features/meal_planner/presentation/controllers/meal_plan_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
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

/// Result of [MealPlanController.addMealToToday]: what landed where, what it
/// replaced (for Undo) and the user's allergens it may contain.
class AddedMeal {
  const AddedMeal({
    required this.date,
    required this.slot,
    required this.recipe,
    this.replaced,
    this.allergenConflicts = const [],
  });

  final DateTime date;
  final MealSlot slot;
  final Recipe recipe;
  final Recipe? replaced;
  final List<String> allergenConflicts;
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

  /// "Tạo thực đơn" / "Tạo lại thực đơn": a whole AI week. [fromPantry]
  /// builds it around "Nguyên liệu trong tủ" ("Tạo thực đơn từ tủ lạnh").
  ///  when generation failed (the screen shows the error).
  Future<bool> generatePlan({bool fromPantry = false}) async {
    final previous = state.valueOrNull ?? await future;
    state = const AsyncLoading<MealPlannerState>();
    state = await AsyncValue.guard(() async {
      final dto = await _api.generateMealPlan(
          startDate: startOfWeek(DateTime.now()), fromPantry: fromPantry);
      final plan = dto.toEntity();
      return previous.copyWith(plan: plan, selectedDate: _initialDate(plan));
    });
    return state.hasValue && !state.hasError;
  }

  /// "Tự lên thực đơn": an empty week, filled slot by slot.
  Future<void> createEmptyPlan() async {
    final previous = state.valueOrNull ?? await future;
    state = const AsyncLoading<MealPlannerState>();
    state = await AsyncValue.guard(() async {
      final dto = await _api.createEmptyMealPlan(
          startDate: startOfWeek(DateTime.now()));
      final plan = dto.toEntity();
      return previous.copyWith(plan: plan, selectedDate: _initialDate(plan));
    });
  }

  /// Saves the health profile, keeps the plan on screen with the new
  /// profile and refreshes the allergies other features read. Throws on
  /// failure so the form keeps the input.
  Future<HealthProfile> updateHealthProfile({
    required double heightCm,
    required double weightKg,
    required HealthGoal goal,
    required List<String> allergies,
    required List<String> dietaryRestrictions,
  }) async {
    final saved = (await _api.updateHealthProfile(UpdateHealthProfileRequestDto(
      heightCm: heightCm,
      weightKg: weightKg,
      goal: goal,
      allergies: allergies,
      dietaryRestrictions: dietaryRestrictions,
    )))
        .toEntity();
    if (state.valueOrNull case final current?) {
      state = AsyncData(current.copyWith(profile: saved));
    } else {
      ref.invalidateSelf();
    }
    ref.invalidate(userAllergiesProvider);
    return saved;
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

  /// Puts [replacement] (AI suggestion, own recipe, chef suggestion, or the
  /// recipe being restored by Undo) in the selected day's [slot], keeping its
  /// [Recipe.source]. Optimistic with rollback. Returns the replaced recipe
  /// (`null` when the slot was empty).
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
          date: day.date,
          slot: slot,
          recipeId: replacement.id,
          source: replacement.source,
        ),
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
          date: day.date,
          slot: slot,
          recipeId: seasonal.recipeId,
          source: MealSource.ai,
        ),
      );
      _applyServerDay(serverDay.toEntity());
      return previous;
    } catch (_) {
      _applyServerDay(day);
      rethrow;
    }
  }

  /// "Thêm vào thực đơn" from the fridge scan: puts the dish in today's
  /// [slot] (replacing the planned meal) and selects today, so the Thực đơn
  /// tab shows it. Works even if the tab was never opened (awaits the first
  /// load). Allergens are flagged like any planned meal, not blocked.
  Future<AddedMeal> addMealToToday({
    required MealSlot slot,
    required String name,
    required int calories,
    int? prepMinutes,
    List<String> ingredients = const [],
    List<String> allergens = const [],
    String? sourceId,
  }) async {
    final s = await future;
    final today = dateOnly(DateTime.now());
    final day = s.plan?.dayFor(today);
    if (day == null) {
      throw const ApiException(
        message:
            'Bạn chưa có thực đơn tuần này. Vào tab Thực đơn để tạo trước nhé.',
        statusCode: 404,
      );
    }

    final serverDay = (await _api.addMealToCurrentPlan(
      AddMealRequestDto(
        date: today,
        slot: slot,
        name: name,
        calories: calories,
        prepMinutes: prepMinutes,
        ingredients: ingredients,
        allergens: allergens,
        sourceId: sourceId,
      ),
    ))
        .toEntity();

    final latest = state.valueOrNull ?? s;
    final plan = latest.plan ?? s.plan!;
    state = AsyncData(
        latest.copyWith(plan: plan.replaceDay(serverDay), selectedDate: today));

    final recipe = serverDay.meals[slot]!;
    return AddedMeal(
      date: today,
      slot: slot,
      recipe: recipe,
      replaced: day.meals[slot],
      allergenConflicts: recipe.allergenConflicts(latest.profile.allergies),
    );
  }

  /// Undo for [addMealToToday] / [addManualMeal]: puts the replaced recipe
  /// back, or empties the slot again if it was empty.
  Future<void> undoAddMeal(AddedMeal added) async {
    final replaced = added.replaced;
    final plan = state.valueOrNull?.plan;
    if (plan == null) return;
    final serverDay = replaced == null
        ? await _api.removeMeal(
            planId: plan.id, date: added.date, slot: added.slot)
        : await _api.swapMeal(
            planId: plan.id,
            request: SwapMealRequestDto(
              date: added.date,
              slot: added.slot,
              recipeId: replaced.id,
              source: replaced.source,
            ),
          );
    _applyServerDay(serverDay.toEntity());
  }

  /// "Tự nhập món": a dish typed in for the selected day's [slot]. kcal and
  /// macros are optional; the server flags allergens found in the name.
  Future<AddedMeal> addManualMeal({
    required MealSlot slot,
    required String name,
    int? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) async {
    final s = state.requireValue;
    final day = s.selectedDay;
    if (s.plan == null || day == null) {
      throw const ApiException(
          message: 'Hãy tạo thực đơn tuần này trước nhé.', statusCode: 404);
    }
    state = AsyncData(s.copyWith(swappingSlot: slot));
    try {
      final serverDay = (await _api.addMealToCurrentPlan(AddMealRequestDto(
        date: day.date,
        slot: slot,
        name: name,
        calories: calories,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        source: MealSource.manual.apiValue,
      )))
          .toEntity();
      _applyServerDay(serverDay);
      final recipe = serverDay.meals[slot]!;
      return AddedMeal(
        date: day.date,
        slot: slot,
        recipe: recipe,
        replaced: day.meals[slot],
        allergenConflicts: recipe.allergenConflicts(s.profile.allergies),
      );
    } catch (_) {
      _applyServerDay(day);
      rethrow;
    }
  }

  /// "Bỏ món": empties the selected day's [slot]. Returns what was there.
  Future<Recipe?> removeMeal(MealSlot slot) async {
    final s = state.requireValue;
    final plan = s.plan;
    final day = s.selectedDay;
    final previous = day?.meals[slot];
    if (plan == null || day == null || previous == null) return null;
    state = AsyncData(s.copyWith(swappingSlot: slot));
    try {
      final serverDay =
          await _api.removeMeal(planId: plan.id, date: day.date, slot: slot);
      _applyServerDay(serverDay.toEntity());
      return previous;
    } catch (_) {
      _applyServerDay(day);
      rethrow;
    }
  }

  /// "Công thức của tôi".
  Future<List<Recipe>> fetchMyRecipes() async =>
      (await _api.getMyRecipes()).map((r) => r.toEntity()).toList();

  Future<Recipe> createMyRecipe(CreateRecipeRequestDto request) async =>
      (await _api.createMyRecipe(request)).toEntity();

  /// "Từ chuyên gia".
  Future<List<ChefSuggestion>> fetchChefSuggestions() async =>
      (await _api.getChefSuggestions()).map((s) => s.toEntity()).toList();

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
