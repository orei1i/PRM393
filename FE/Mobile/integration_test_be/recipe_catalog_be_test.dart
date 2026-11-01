// integration_test_be/recipe_catalog_be_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/recipe/data/backend_recipe_items.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_api_service.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';
import 'package:veganlife_mobile/features/recipe/presentation/controllers/recipe_customization_controller.dart';

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

  group('recipe catalog', skip: be.skipReason, () {
    late BeUser me;

    setUpAll(() async {
      me = await be.newUser(name: 'FE IT Catalog');
    });

    beTest('no plan this week: at most 10, and no plan is created', () async {
      final user = await be.newUser(name: 'FE IT Catalog No Plan');
      final recipes = await RecipeCatalog(user.dio, userId: user.id).load();
      expect(recipes, isNotEmpty);
      expect(recipes.length, lessThanOrEqualTo(10));
      expect((await user.raw('GET', '/meal-plans/current')).status, 404);
    });

    beTest('with a plan: at least 29 recipes, each one with rows to show',
        () async {
      await RemoteMealPlannerApiService(me.dio).updateHealthProfile(_profile);
      await RemoteMealPlannerApiService(me.dio)
          .generateMealPlan(startDate: startOfWeek(DateTime.now()));
      final recipes = await RecipeCatalog(me.dio, userId: me.id).load();
      expect(recipes.length, greaterThanOrEqualTo(29));
      for (final r in recipes) {
        expect(r.id, hasLength(24), reason: r.name);
        expect(r.isVegan, isTrue, reason: r.name);
        expect(r.ingredients, isNotEmpty, reason: r.name);
      }
    });

    beTest('it finds every recipe of a generated plan', () async {
      final c = await me.container();
      addTearDown(c.dispose);
      await c.read(mealPlannerApiProvider).updateHealthProfile(_profile);
      await c.read(mealPlanControllerProvider.future);
      final notifier = c.read(mealPlanControllerProvider.notifier);
      expect(await notifier.generatePlan(), isTrue);
      final plan = c.read(mealPlanControllerProvider).requireValue.plan!;

      final catalog = c.read(recipeCatalogProvider);
      for (final day in plan.days) {
        for (final dish in day.meals.values) {
          expect(await catalog.find(dish.id), isNotNull, reason: dish.name);
        }
      }
    });

    beTest('a peanut allergy leaves peanut recipes out of the catalogue',
        () async {
      final allergic = await be.newUser(name: 'FE IT Catalog Allergy');
      await RemoteMealPlannerApiService(allergic.dio).updateHealthProfile(
        const UpdateHealthProfileRequestDto(
          heightCm: 170,
          weightKg: 66,
          goal: HealthGoal.maintain,
          allergies: ['peanut'],
          dietaryRestrictions: [],
          gender: Gender.female,
          birthYear: 1997,
          activityLevel: ActivityLevel.light,
          mealPattern: [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner],
        ),
      );
      final recipes =
          await RecipeCatalog(allergic.dio, userId: allergic.id).load();
      expect(recipes, isNotEmpty);
      for (final r in recipes) {
        expect(r.allergens, isNot(contains('peanut')), reason: r.name);
      }

      // Its page still opens: the screen flags the allergen instead of a 404.
      final all = await RecipeCatalog(me.dio, userId: me.id).load();
      final peanut = all.firstWhere((r) => r.allergens.contains('peanut'));
      final page = await RecipeCatalog(allergic.dio, userId: allergic.id)
          .find(peanut.id);
      expect(page?.allergens, contains('peanut'));
    });

    beTest('B4: another member\'s private recipe stays private', () async {
      final owner = await be.newUser(name: 'FE IT Catalog Owner');
      final created = await RemoteMealPlannerApiService(owner.dio)
          .createMyRecipe(const CreateRecipeRequestDto(
              name: 'Món riêng tư FE IT',
              calories: 500,
              ingredients: [
            RecipeIngredientInput(name: 'Đậu hũ', quantity: 0, unit: ''),
          ],
              steps: [
            'Nấu'
          ]));

      final own =
          await RecipeCatalog(owner.dio, userId: owner.id).find(created.id);
      expect(own?.createdBy, owner.id);

      final catalog = RecipeCatalog(me.dio, userId: me.id);
      expect(await catalog.find(created.id), isNull);
      expect((await catalog.load()).map((r) => r.name),
          isNot(contains('Món riêng tư FE IT')));
    });

    beTest('B19: POST /recipes keeps prepMinutes and a 0', () async {
      final res = await me.raw('POST', '/recipes', data: {
        'name': 'Món B19',
        'calories': 0,
        'prepMinutes': 20,
        'ingredients': ['Đậu hũ'],
        'instructions': ['Nấu'],
      });
      expect(res.status, 201);
      expect(res.dataMap['prepMinutes'], 20);
      expect(res.dataMap['calories'], 0);
    });

    beTest('every seed recipe gets its table, with the BE rows and kcal',
        () async {
      await RemoteMealPlannerApiService(me.dio).updateHealthProfile(_profile);
      await RemoteMealPlannerApiService(me.dio)
          .generateMealPlan(startDate: startOfWeek(DateTime.now()));
      final raw = (await me.raw('GET', '/meal-plans/current')).dataMap;
      final rows = (await me
              .raw('GET', '/meal-plans/${raw['id']}/swap-suggestions', query: {
        'date': '2000-01-01',
        'slot': 'snack_am',
        'limit': 200,
      }))
          .dataList;
      final seeds =
          rows.where((r) => backendRecipeItemsFor('${r['name']}') != null);
      expect(seeds, hasLength(29));
      for (final row in seeds) {
        final recipe = recipeFromBackend(row).toEntity();
        expect([for (final i in recipe.ingredients) i.name], row['ingredients'],
            reason: recipe.name);
        expect(recipe.caloriesCache, row['calories'], reason: recipe.name);
        expect(recipe.isReadOnly, isFalse, reason: recipe.name);
        final items = backendRecipeItemsFor(recipe.name)!;
        final kcal = items.rows.fold<double>(
            0,
            (sum, r) =>
                sum +
                ((r['nutrition']! as Map<String, Object?>)['calories']!
                    as num));
        expect(kcal / items.servings,
            closeTo(row['calories'] as num, (row['calories'] as num) * 0.1),
            reason: recipe.name);
      }
    });

    beTest('the table uses the per-100 g figures of GET /ingredients',
        () async {
      final catalog = {
        for (final i in (await me.raw('GET', '/ingredients')).dataList)
          i['name']: i,
      };
      var checked = 0;
      for (final dish in backendRecipeItemsJson()) {
        for (final row in (dish['ingredientItems']! as List<Object?>)
            .cast<Map<String, Object?>>()) {
          final food = catalog[row['name']];
          final unit = row['unit']! as String;
          if (food == null || !(unit == 'g' || unit.startsWith('g '))) continue;
          final kcal = (food['caloriesPer100g'] as num) *
              (row['quantity']! as num) /
              100;
          expect((row['nutrition']! as Map<String, Object?>)['calories'],
              closeTo(kcal, 0.1),
              reason: '${dish['name']} / ${row['name']}');
          expect(row['allergens'], food['allergens'], reason: '${row['name']}');
          checked++;
        }
      }
      expect(checked, greaterThan(50));
    });

    beTest(
        'a changed seed recipe: POST /recipes, reopened with its origin and '
        'signature rows, placed in the plan', () async {
      final c = await me.container();
      addTearDown(c.dispose);
      await c.read(mealPlannerApiProvider).updateHealthProfile(_profile);
      await c.read(mealPlanControllerProvider.future);
      expect(await c.read(mealPlanControllerProvider.notifier).generatePlan(),
          isTrue);

      final all = await c.read(recipeCatalogProvider).load();
      final recipe = all
          .firstWhere((r) => r.name == 'Đậu hũ sốt cà chua & cơm lứt')
          .toEntity();
      final sub = c.listen(recipeCustomizationProvider(recipe.id), (_, __) {});
      addTearDown(sub.close);
      final notifier = c.read(recipeCustomizationProvider(recipe.id).notifier);
      notifier.swap(recipe.ingredient('dau_hu')!, 'dau_hu_nam_dui_ga');

      final saved = await notifier.saveVariant(recipe, 'Biến thể FE IT');
      expect(saved.id, hasLength(24));
      expect(saved.caloriesCache, lessThan(recipe.caloriesCache!));
      expect(saved.createdBy, me.id);

      final back =
          (await c.read(recipeApiProvider).getRecipe(saved.id)).toEntity();
      expect(back.name, 'Biến thể FE IT');
      expect(back.caloriesCache, saved.caloriesCache);
      expect(back.proteinG, saved.proteinG);
      expect(back.allergens, contains('soy'),
          reason: 'the soy sauce is still there');
      expect(back.basedOnName, recipe.name);
      expect(back.nutritionEstimated, isTrue);
      expect(back.servings, 2);
      expect(back.steps, recipe.steps);
      expect(back.isPublic, isFalse);
      final swapped = back.ingredient('dau_hu')!;
      expect(swapped.name, 'Nấm đùi gà');
      expect(swapped.amount, '400 g');
      expect(swapped.isSignature, isTrue);
      expect(swapped.substitutes.map((s) => s.name), contains('Đậu hũ'));

      final mine = await c.read(mealPlannerApiProvider).getMyRecipes();
      expect(mine.map((r) => r.id), contains(saved.id));

      // Same changes: reused, not saved twice; the slot holds the variant.
      final plan = c.read(mealPlanControllerProvider).requireValue.plan!;
      final placed = await notifier.addToPlan(recipe,
          date: plan.days.first.date, slot: MealSlot.dinner);
      expect(placed.recipe.id, saved.id);
      expect(await c.read(mealPlannerApiProvider).getMyRecipes(),
          hasLength(mine.length));
    });

    beTest('a saved copy can be saved again as a new one: both stay', () async {
      final api = RemoteMealPlannerApiService(me.dio);
      final first = await api.createMyRecipe(const CreateRecipeRequestDto(
          name: 'Bản cũ FE IT',
          calories: 400,
          ingredients: [
            RecipeIngredientInput(name: 'Đậu hũ', quantity: 200, unit: 'g'),
          ],
          steps: [
            'Nấu'
          ]));
      expect(first.allergens, ['soy'], reason: 'the BE works nothing out');
      final copy = await api.createMyRecipe(const CreateRecipeRequestDto(
          name: 'Bản cũ FE IT (bản mới)',
          calories: 380,
          ingredients: [
            RecipeIngredientInput(name: 'Nấm rơm', quantity: 200, unit: 'g'),
          ],
          steps: [
            'Nấu'
          ]));
      final ids = (await api.getMyRecipes()).map((r) => r.id);
      expect(ids, containsAll([first.id, copy.id]));
      // Nothing to overwrite or remove with yet (BackendModules.myRecipeEdit).
      expect(
          (await me.raw('PUT', '/recipes/${first.id}', data: {})).status, 405);
      expect((await me.raw('DELETE', '/recipes/${first.id}')).status, 405);
    });

    beTest('page routing: 24-hex, unknown, and a mock id', () async {
      final catalog = RecipeCatalog(me.dio, userId: me.id);
      final snapshots = PlanItemSnapshots();
      final pages = RemoteRecipeApiService(
        catalog: () => catalog,
        snapshots: () => snapshots,
      );

      final known = (await catalog.load()).first;
      final page = await pages.getRecipe(known.id);
      expect(page.name, known.name);
      expect(page.instructions, isNotEmpty);

      await expectApiError(
        pages.getRecipe('000000000000000000000000'),
        status: 404,
        code: 'not_found',
      );
      await expectApiError(
        pages.getRecipe('00000000000000000000000000000000'),
        status: 404,
        code: 'not_found',
      );
      expect((await pages.getRecipe('l5')).name, isNotEmpty);
    });

    beTest('a guest reaches mock recipes; a real id reads as an error',
        () async {
      final c = await guestContainer();
      addTearDown(c.dispose);
      final pages = c.read(recipeApiProvider);
      expect((await pages.getRecipe('l5')).name, isNotEmpty);
      await expectApiError(
        pages.getRecipe('000000000000000000000000'),
        status: 401,
      );
    });
  });
}
