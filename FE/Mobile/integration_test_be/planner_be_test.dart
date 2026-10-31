// integration_test_be/planner_be_test.dart
//
// One account's week, in order: each test continues from the last one.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/utils/backend_ids.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_api_service.dart';

import 'be_harness.dart';

Future<void> main() async {
  final be = await BeHarness.start();

  group('planner', skip: be.skipReason, () {
    late ProviderContainer c;

    MealPlanController notifier() =>
        c.read(mealPlanControllerProvider.notifier);
    MealPlannerState state() => c.read(mealPlanControllerProvider).requireValue;
    Recipe? meal(MealSlot slot) => state().selectedDay!.meals[slot];
    const pattern = [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner];

    setUpAll(() async {
      final me = await be.newUser(name: 'FE IT Planner');
      c = await me.container();
    });

    tearDownAll(() => c.dispose());

    beTest('a new account has no plan', () async {
      final planner = c.read(mealPlannerApiProvider);
      expect(await planner.getCurrentMealPlan(), isNull);
    });

    beTest('generate with a peanut allergy: no peanut-tagged dish', () async {
      await c.read(mealPlannerApiProvider).updateHealthProfile(
            const UpdateHealthProfileRequestDto(
              heightCm: 170,
              weightKg: 66,
              goal: HealthGoal.loseWeight,
              allergies: ['peanut', 'lá lốt'],
              dietaryRestrictions: [],
              gender: Gender.female,
              birthYear: 1997,
              activityLevel: ActivityLevel.light,
              mealPattern: pattern,
            ),
          );
      await c.read(mealPlanControllerProvider.future);
      expect(await notifier().generatePlan(), isTrue);

      final plan = state().plan!;
      expect(plan.days, hasLength(7));
      expect(isSameDay(plan.startDate, startOfWeek(DateTime.now())), isTrue);
      final dishes = [
        for (final day in plan.days) ...day.meals.values,
      ];
      expect(dishes, isNotEmpty);
      for (final dish in dishes) {
        expect(dish.allergens, isNot(contains('peanut')), reason: dish.name);
        expect(isBackendId(dish.id), isTrue, reason: dish.name);
      }
    });

    beTest('swap keeps the macros and opens the recipe; undo restores',
        () async {
      final first = state().selectedDay!.meals.entries.first;
      final suggestions = await notifier().fetchSwapSuggestions(first.key);
      expect(suggestions, isNotEmpty);
      for (final s in suggestions) {
        expect(s.allergens, isNot(contains('peanut')), reason: s.name);
      }

      final replaced = await notifier().swapMeal(first.key, suggestions.first);
      expect(replaced!.id, first.value.id);
      final swapped = meal(first.key)!;
      expect(swapped.id, suggestions.first.id);
      expect(swapped.hasDetail, isTrue);
      expect(swapped.nutrition.proteinG, isNotNull);
      expect(swapped.nutrition.carbsG, isNotNull);
      expect(swapped.nutrition.fatG, isNotNull);

      await notifier().swapMeal(first.key, replaced);
      expect(meal(first.key)!.id, first.value.id);
    });

    beTest('the placed dish opens a recipe page', () async {
      final dish = state().selectedDay!.meals.values.first;
      final page = await c.read(recipeApiProvider).getRecipe(dish.id);
      expect(page.name, dish.name);
      expect(page.ingredients, isNotEmpty);
      expect(page.isSnapshot, isFalse);
    });

    beTest('a typed dish: its own id, a snapshot page, and undo', () async {
      final typed = await notifier().addManualMeal(
          slot: MealSlot.snackLate,
          name: 'Canh chua nấm tự nấu',
          calories: 200);
      expect(isBackendPlanItemId(typed.recipe.id), isTrue);
      expect(typed.recipe.source, MealSource.manual);
      final page = await c.read(recipeApiProvider).getRecipe(typed.recipe.id);
      expect(page.isSnapshot, isTrue);

      final before = meal(MealSlot.lunch)!;
      final added = await notifier().addManualMeal(
          slot: MealSlot.lunch, name: 'Món gõ tay', calories: 300);
      expect(meal(MealSlot.lunch)!.name, 'Món gõ tay');
      await notifier().undoAddMeal(added);
      expect(meal(MealSlot.lunch)!.id, before.id);
    });

    beTest('undo back to a typed dish goes through POST', () async {
      final suggestions = await notifier().fetchSwapSuggestions(MealSlot.lunch);
      final over =
          await notifier().swapMeal(MealSlot.snackLate, suggestions.first);
      expect(over!.name, 'Canh chua nấm tự nấu');
      await notifier().swapMeal(MealSlot.snackLate, over);
      final restored = meal(MealSlot.snackLate)!;
      expect(restored.name, 'Canh chua nấm tự nấu');
      expect(restored.source, MealSource.manual);
    });

    beTest('a mock recipe is placed by POST with its id, and can be removed',
        () async {
      await notifier().swapMeal(
        MealSlot.snackAm,
        const Recipe(
          id: 'l5',
          name: 'Bún riêu chay',
          nutrition: Nutrition(calories: 580),
          source: MealSource.recipe,
        ),
      );
      expect(meal(MealSlot.snackAm)!.id, 'l5');
      final page = await c.read(recipeApiProvider).getRecipe('l5');
      expect(page.name, isNotEmpty);

      await notifier().removeMeal(MealSlot.snackAm);
      expect(meal(MealSlot.snackAm), isNull);
    });

    beTest('"Từ chuyên gia" comes from the mock persona while bookings is mock',
        () async {
      expect(await notifier().fetchChefSuggestions(), isNotEmpty);
    });

    beTest('"Áp dụng kế hoạch": a batch lands on the real plan', () async {
      final placed = await notifier().addMeals([
        AddMealRequestDto(
          date: DateTime.now(),
          slot: MealSlot.snackPm,
          name: 'Sinh tố từ chuyên gia',
          calories: 150,
          source: MealSource.chef.apiValue,
          sourceId: 'cs_mock',
          sourceName: 'Bếp thử',
        ),
      ]);
      expect(placed, 1);
      final dish = meal(MealSlot.snackPm)!;
      expect(dish.name, 'Sinh tố từ chuyên gia');
      expect(dish.source, MealSource.chef);
    });

    beTest('a new goal re-aims the week on the app (B8 workaround)', () async {
      await notifier().updateHealthProfile(
        heightCm: 170,
        weightKg: 66,
        goal: HealthGoal.gainWeight,
        allergies: const ['peanut', 'lá lốt'],
        dietaryRestrictions: const [],
        mealPattern: state().pattern,
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(
          state().plan!.dailyTargets.calories, state().profile.targetCalories);
      expect(state().profile.birthYear, 1997);
      expect(state().profile.gender, Gender.female);
    });

    beTest('"Công thức của tôi": create, list, open', () async {
      final mine = await notifier().createMyRecipe(const CreateRecipeRequestDto(
        name: 'Cơm thử tích hợp',
        calories: 480,
        ingredients: [
          RecipeIngredientInput(name: 'Đậu hũ', quantity: 200, unit: 'g'),
          RecipeIngredientInput(name: 'Cà chua', quantity: 0, unit: ''),
        ],
        steps: ['Nấu', 'Ăn'],
      ));
      expect(mine.source, MealSource.userRecipe);
      expect(mine.createdBy, isNotNull);
      final mineList = await notifier().fetchMyRecipes();
      expect(mineList.any((r) => r.id == mine.id), isTrue);

      final page = await c.read(recipeApiProvider).getRecipe(mine.id);
      expect(page.createdBy, isNotNull);
      expect(page.ingredients, hasLength(2));
    });

    beTest('"Tự lên thực đơn": a new account gets an empty week', () async {
      final other = await be.newUser(name: 'FE IT Planner Empty');
      final planner = RemoteMealPlannerApiService(other.dio);
      final plan = await planner.createEmptyMealPlan(
          startDate: startOfWeek(DateTime.now()));
      expect(plan.days, hasLength(7));
      expect(plan.days.expand((d) => d.meals.values), isEmpty);
    });

    beTest('generate from the fridge', () async {
      expect(await notifier().generatePlan(fromPantry: true), isTrue);
      expect(state().plan!.days, hasLength(7));
    });
  });
}
