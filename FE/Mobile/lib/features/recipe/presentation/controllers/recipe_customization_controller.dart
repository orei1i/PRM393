// lib/features/recipe/presentation/controllers/recipe_customization_controller.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../meal_planner/data/meal_planner_api_service.dart';
import '../../../meal_planner/domain/entities/health_profile.dart';
import '../../../meal_planner/domain/entities/meal_plan.dart';
import '../../../meal_planner/presentation/controllers/meal_plan_controller.dart';
import '../../data/models/recipe_variant_model.dart';
import '../../data/recipe_community_api_service.dart';
import '../../domain/entities/recipe_detail.dart';
import '../../domain/recipe_customization.dart';
import '../../domain/recipe_scaling.dart';

/// What the recipe page keeps for one recipe: the cook's choices, the meal
/// they compare it with, and the variants saved from these choices.
class RecipeCustomizationState {
  const RecipeCustomizationState({
    this.choices = const RecipeCustomization(),
    this.compareSlot,
    this.savedVariants = const {},
  });

  final RecipeCustomization choices;

  /// "So với mục tiêu: [Bữa …]" picked by the cook; `null` → the default.
  final MealSlot? compareSlot;

  /// Variants saved from this page, by [RecipeCustomization.choicesKey]:
  /// "Thêm vào Thực đơn" reuses the one saved for the same changes.
  final Map<String, RecipeDetail> savedVariants;

  RecipeDetail? get savedForChoices => savedVariants[choices.choicesKey];

  RecipeCustomizationState copyWith({
    RecipeCustomization? choices,
    MealSlot? compareSlot,
    Map<String, RecipeDetail>? savedVariants,
  }) =>
      RecipeCustomizationState(
        choices: choices ?? this.choices,
        compareSlot: compareSlot ?? this.compareSlot,
        savedVariants: savedVariants ?? this.savedVariants,
      );
}

/// The cook's preview on a recipe page, by recipe id. Guests can use it all;
/// it doesn't depend on the session, so signing in (to save or add to the
/// plan) keeps the changes. Dropped when the page closes.
final recipeCustomizationProvider = NotifierProvider.autoDispose
    .family<RecipeCustomizationController, RecipeCustomizationState, String>(
        RecipeCustomizationController.new);

/// Result of [RecipeCustomizationController.addToPlan].
class PlacedRecipe {
  const PlacedRecipe(
      {required this.recipe, required this.date, required this.slot});

  /// What the slot now holds (the saved variant for a changed recipe).
  final Recipe recipe;
  final DateTime date;
  final MealSlot slot;
}

class RecipeCustomizationController
    extends AutoDisposeFamilyNotifier<RecipeCustomizationState, String> {
  @override
  RecipeCustomizationState build(String recipeId) =>
      const RecipeCustomizationState();

  RecipeCustomization get _choices => state.choices;

  void _set(RecipeCustomization choices) =>
      state = state.copyWith(choices: choices);

  /// "Nấu cho N người" (1–20); [base] clears it.
  void setServings(int servings, {required int base}) {
    final n = servings.clamp(minServings, maxServings);
    _set(n == base
        ? _choices.copyWith(clearServings: true)
        : _choices.copyWith(servings: n));
  }

  /// "Đổi": [substituteKey] for [row] (must be one of its substitutes).
  void swap(RecipeIngredient row, String substituteKey) {
    if (row.substitute(substituteKey) == null) return;
    _set(_choices.copyWith(
      swaps: {..._choices.swaps, row.key: substituteKey},
      removed: {..._choices.removed}..remove(row.key),
    ));
  }

  /// "Hoàn tác" / "Giữ nguyên".
  void undoSwap(String rowKey) =>
      _set(_choices.copyWith(swaps: {..._choices.swaps}..remove(rowKey)));

  /// "Bỏ {tên}". A "Thành phần chính" row can't be left out: returns
  /// `false` and changes nothing.
  bool remove(RecipeIngredient row) {
    if (row.isSignature) return false;
    _set(_choices.copyWith(
      removed: {..._choices.removed, row.key},
      swaps: {..._choices.swaps}..remove(row.key),
    ));
    return true;
  }

  /// "Thêm lại".
  void restore(String rowKey) =>
      _set(_choices.copyWith(removed: {..._choices.removed}..remove(rowKey)));

  /// "Đặt lại": back to the recipe's ingredients (servings kept).
  void resetIngredients() =>
      _set(_choices.copyWith(swaps: const {}, removed: const {}));

  void selectCompareSlot(MealSlot slot) =>
      state = state.copyWith(compareSlot: slot);

  /// "Lưu thành công thức của tôi": saves the current changes to
  /// [recipe] as a private recipe named [name]. Throws `ApiException`.
  Future<RecipeDetail> saveVariant(RecipeDetail recipe, String name) async {
    final choices = _choices;
    final dto = await ref.read(recipeCommunityApiProvider).createVariant(
        recipe.id, CreateVariantRequestDto.fromChoices(name, choices));
    final variant = dto.toEntity();
    state = state.copyWith(savedVariants: {
      ...state.savedVariants,
      choices.choicesKey: variant,
    });
    return variant;
  }

  /// "Thêm vào Thực đơn": one serving of the dish as previewed in [slot] of
  /// [date] (a day of the current week). A changed recipe is saved first
  /// (or the variant saved for the same changes is reused) and placed as
  /// "Công thức của tôi"; a catalogue recipe as "Từ công thức". Throws
  /// `ApiException` (the plan is rolled back by the planner).
  Future<PlacedRecipe> addToPlan(RecipeDetail recipe,
      {required DateTime date, required MealSlot slot}) async {
    final choices = _choices;
    final RecipeDetail placed;
    final MealSource source;
    if (choices.isModified) {
      placed = state.savedForChoices ??
          await saveVariant(recipe, defaultVariantName(recipe.name));
      source = MealSource.userRecipe;
    } else {
      placed = recipe;
      final mine = {
        ref.read(plannerUserIdProvider),
        ref.read(plannerPersonaIdProvider),
      };
      source = recipe.isPublic
          ? MealSource.recipe
          : mine.contains(recipe.createdBy)
              ? MealSource.userRecipe
              : MealSource.chef;
    }
    final meal = Recipe(
      id: placed.id,
      name: placed.name,
      imageUrl: placed.imageUrl,
      nutrition: Nutrition(
        calories: placed.caloriesCache ?? 0,
        proteinG: placed.proteinG,
        carbsG: placed.carbsG,
        fatG: placed.fatG,
        fiberG: placed.fiberG,
      ),
      allergens: placed.allergens,
      prepMinutes: placed.prepMinutes,
      source: source,
      sourceName: source == MealSource.chef ? placed.createdByName : null,
      createdBy: placed.createdBy,
    );
    await ref.read(mealPlanControllerProvider.future);
    final planner = ref.read(mealPlanControllerProvider.notifier)
      ..selectDate(date);
    await planner.swapMeal(slot, meal);
    final day = ref
        .read(mealPlanControllerProvider)
        .valueOrNull
        ?.plan
        ?.dayFor(date)
        ?.meals[slot];
    return PlacedRecipe(recipe: day ?? meal, date: date, slot: slot);
  }
}

/// kcal targets of the member's meals ("Các bữa trong ngày"), or empty
/// without an energy estimate.
Map<MealSlot, int> slotTargets(HealthProfile profile) {
  final daily = profile.dailyKcalTarget;
  if (daily == null) return const {};
  return MealPattern.kcalTargets(profile.mealPattern, daily);
}
