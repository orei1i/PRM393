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
import 'package:veganlife_mobile/features/meal_planner/domain/entities/plan_adjustment.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_api_service.dart';

import 'be_harness.dart';

const _profile = UpdateHealthProfileRequestDto(
  heightCm: 170,
  weightKg: 66,
  goal: HealthGoal.maintain,
  allergies: [],
  dietaryRestrictions: [],
  gender: Gender.female,
  birthYear: 1997,
  activityLevel: ActivityLevel.light,
  mealPattern: [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner],
);

Future<void> main() async {
  final be = await BeHarness.start();

  group('planner', skip: be.skipReason, () {
    late BeUser me;
    late ProviderContainer c;

    MealPlanController notifier() =>
        c.read(mealPlanControllerProvider.notifier);
    MealPlannerState state() => c.read(mealPlanControllerProvider).requireValue;
    Recipe? meal(MealSlot slot) => state().selectedDay!.meals[slot];
    const pattern = [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner];

    setUpAll(() async {
      me = await be.newUser(name: 'FE IT Planner');
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
      expect(
          meal(first.key)!.nutrition.calories, first.value.nutrition.calories,
          reason: 'B6: the portion went back with it');
    });

    beTest('B31: the numbers shown are for the portion, like the BE total',
        () async {
      final res = await me.raw('GET', '/meal-plans/current');
      final days =
          (res.dataMap['days'] as List<dynamic>).cast<Map<String, dynamic>>();
      for (final json in days) {
        final day =
            state().plan!.dayFor(DateTime.parse(json['date'] as String))!;
        // A dish's kcal are rounded on their own.
        expect(day.totals.calories,
            closeTo(json['totalCalories'] as num, day.meals.length.toDouble()));
      }
    });

    beTest('B30: the dish in the slot is not offered', () async {
      final slot = state().selectedDay!.meals.entries.first;
      final plan = state().plan!;
      final res = await me
          .raw('GET', '/meal-plans/${plan.id}/swap-suggestions', query: {
        'date': toApiDate(state().selectedDate),
        'slot': slot.key.apiValue,
        'limit': 50,
      });
      expect(res.dataList, isNotEmpty);
      expect(res.dataList.map((r) => r['id']), isNot(contains(slot.value.id)));
    });

    beTest('B6: PATCH keeps the source and the portion', () async {
      final plan = state().plan!;
      final slot = state().selectedDay!.meals.entries.first;
      final suggestions = await notifier().fetchSwapSuggestions(slot.key);
      final res = await me.raw('PATCH', '/meal-plans/${plan.id}/meals', data: {
        'date': toApiDate(state().selectedDate),
        'slot': slot.key.apiValue,
        'recipeId': suggestions.first.id,
        'source': 'recipe',
        'portion': 2,
      });
      final placed = (res.dataMap['meals'] as Map)[slot.key.apiValue] as Map;
      expect(placed['source'], 'recipe');
      expect(placed['portion'], 2);
      await notifier().swapMeal(slot.key, slot.value);
    });

    beTest('B26: another member gets 404 on this plan, whatever the route',
        () async {
      final plan = state().plan!;
      final other = await be.newUser(name: 'FE IT Planner Other');
      final date = toApiDate(state().selectedDate);
      for (final (method, path, data) in [
        ('GET', '/meal-plans/${plan.id}', null),
        (
          'GET',
          '/meal-plans/${plan.id}/swap-suggestions?date=$date&slot=lunch',
          null
        ),
        ('DELETE', '/meal-plans/${plan.id}/meals?date=$date&slot=lunch', null),
        (
          'PATCH',
          '/meal-plans/${plan.id}/meals',
          {'date': date, 'slot': 'lunch', 'recipeId': plan.id},
        ),
      ]) {
        expect((await other.raw(method, path, data: data)).status, 404,
            reason: '$method $path');
      }
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

      final macros = await notifier().addManualMeal(
          slot: MealSlot.snackLate,
          name: 'Canh chua nấm tự nấu',
          calories: 200,
          proteinG: 10,
          carbsG: 20,
          fatG: 5);
      expect(macros.recipe.nutrition.proteinG, 10, reason: 'B7');
      expect(macros.recipe.nutrition.carbsG, 20);
      expect(macros.recipe.nutrition.fatG, 5);

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

    beTest('"Chỉnh thực đơn": a proposal changes nothing; applied once',
        () async {
      final user = await be.newUser(name: 'FE IT Planner Adjust');
      final api = RemoteMealPlannerApiService(user.dio, userId: user.id);
      await api.updateHealthProfile(const UpdateHealthProfileRequestDto(
        heightCm: 170,
        weightKg: 66,
        goal: HealthGoal.maintain,
        allergies: [],
        dietaryRestrictions: [],
        gender: Gender.female,
        birthYear: 1997,
        activityLevel: ActivityLevel.light,
        mealPattern: [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner],
      ));
      final monday = startOfWeek(DateTime.now());
      final plan = await api.generateMealPlan(startDate: monday);
      final proposal = await api.adjustPlan(AdjustPlanRequestDto(
        message: 'Nấu nhanh hơn cho cả tuần',
        scope: AdjustScope.week,
        date: monday,
      ));
      expect(proposal.proposalId, isNotEmpty);
      expect(proposal.reply, isVietnamese);
      final changes = proposal.toEntity().changes;
      expect(changes, isNotEmpty, reason: proposal.reply);
      for (final change in changes) {
        expect(change.to, isNotNull, reason: 'a replacement says with what');
      }
      final before = await api.getCurrentMealPlan();
      expect([
        for (final d in before!.days) d.meals.keys.length
      ], [
        for (final d in plan.days) d.meals.keys.length
      ], reason: 'nothing applied yet');

      final first = proposal.changes.first;
      final applied = await api.applyAdjustment(
          proposalId: proposal.proposalId, changeIds: [first.id]);
      final day = applied.days
          .singleWhere((d) => toApiDate(d.date) == toApiDate(first.date));
      expect(day.meals[first.slot]?.name, first.to!.name);
      await expectApiError(
          api.applyAdjustment(
              proposalId: proposal.proposalId, changeIds: [first.id]),
          status: 409,
          code: 'already_applied');
    });

    beTest('"Từ chuyên gia" is empty with no booking: nothing made up',
        () async {
      expect(await notifier().fetchChefSuggestions(), isEmpty);
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
      expect(dish.sourceName, 'Bếp thử', reason: 'B7');
    });

    beTest('B7: a batch keeps macros and the recipe id', () async {
      final res =
          await me.raw('POST', '/meal-plans/current/meals/batch', data: {
        'meals': [
          {
            'date': toApiDate(DateTime.now()),
            'slot': 'snack_am',
            'name': 'Món chuyên gia',
            'calories': 150,
            'proteinG': 10,
            'source': 'chef',
            'sourceName': 'Bếp X',
            'recipeId': '000000000000000000000000',
          },
        ],
      });
      final day = (res.dataMap['days'] as List<dynamic>).first as Map;
      final dish = (day['meals'] as Map)['snack_am'] as Map;
      expect(dish['proteinG'], 10);
      expect(dish['sourceName'], 'Bếp X');
      expect(dish['recipeId'], '000000000000000000000000');
      await notifier().removeMeal(MealSlot.snackAm);
    });

    beTest('B8: a new goal re-aims the week on the BE', () async {
      final before = state().plan!.dailyTargets.calories;
      await notifier().updateHealthProfile(
        heightCm: 170,
        weightKg: 66,
        goal: HealthGoal.gainWeight,
        allergies: const ['peanut', 'lá lốt'],
        dietaryRestrictions: const [],
        mealPattern: state().pattern,
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final raw = await me.raw('GET', '/meal-plans/current');
      final target = state().profile.targetCalories;
      expect(target, greaterThan(before));
      expect((raw.dataMap['dailyTargets'] as Map)['calories'], target);
      expect(raw.dataMap['goal'], 'gain_weight');
      expect(state().plan!.dailyTargets.calories, target);
      expect(state().profile.birthYear, 1997);
      expect(state().profile.gender, Gender.female);
    });

    beTest('B29: "Tự lên thực đơn" empties a filled week, keeping its id',
        () async {
      final plan = state().plan!;
      expect(plan.days.expand((d) => d.meals.values), isNotEmpty);
      await notifier().createEmptyPlan();
      final empty = state().plan!;
      expect(empty.id, plan.id);
      expect(empty.days, hasLength(7));
      expect(empty.days.expand((d) => d.meals.values), isEmpty);
      expect(empty.dailyTargets.calories, plan.dailyTargets.calories);
      expect(await notifier().generatePlan(), isTrue);
      expect(state().plan!.days.expand((d) => d.meals.values), isNotEmpty);
    });

    beTest('B11: generate follows the meal pattern', () async {
      final other = await be.newUser(name: 'FE IT Planner Pattern');
      final planner = RemoteMealPlannerApiService(other.dio);
      await planner.updateHealthProfile(const UpdateHealthProfileRequestDto(
        heightCm: 170,
        weightKg: 66,
        goal: HealthGoal.maintain,
        allergies: [],
        dietaryRestrictions: [],
        gender: Gender.female,
        birthYear: 1997,
        activityLevel: ActivityLevel.light,
        mealPattern: [MealSlot.snackAm, MealSlot.lunch, MealSlot.dinner],
      ));
      final plan = await planner.generateMealPlan(
          startDate: startOfWeek(DateTime.now()));
      for (final day in plan.days) {
        expect(day.meals.keys.toSet(), {'snack_am', 'lunch', 'dinner'});
      }
    });

    beTest('B24: only this week counts as current', () async {
      final other = await be.newUser(name: 'FE IT Planner Old');
      final planner = RemoteMealPlannerApiService(other.dio);
      await planner.updateHealthProfile(_profile);
      await planner.generateMealPlan(
          startDate:
              startOfWeek(DateTime.now().subtract(const Duration(days: 28))));
      expect(await planner.getCurrentMealPlan(), isNull);
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
