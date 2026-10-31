// test/hybrid/recipe_catalog_test.dart
// Recipes on a BE without GET /recipes/{id}: the catalogue, the plan snapshots
// and where each kind of id goes.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_api_service.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';

import 'planner_test_support.dart';

const _suggestions = '/meal-plans/000000000000000000000000/swap-suggestions';
const _mine = '/users/me/recipes';
const _inCatalog = '6ae595c796695f5c139fa99b';

FakeBackend _catalogBackend() => FakeBackend()
  ..on('GET $_suggestions', 200, fixture('recipe_fixture_swap.json'))
  ..on(
      'GET $_mine',
      200,
      envelope([
        {
          'id': '6ae5962596695f5c139fa9b6',
          'name': 'Cơm của tôi',
          'calories': 500,
          'allergens': <String>[],
          'ingredients': ['Cơm 200 g'],
          'instructions': ['Nấu', 'Ăn'],
        },
      ]));

void main() {
  setUp(() => BackendModules.debugOverride(BackendModules.supportedByBackend));
  tearDown(() => BackendModules.debugOverride(null));

  group('RecipeCatalog', () {
    test('asks for everything with the slot no recipe is tagged with',
        () async {
      final backend = _catalogBackend();
      final c = await backendContainer(backend);
      final all = await c.read(recipeCatalogProvider).load();
      expect(all.length, 4);
      final query =
          backend.requests('GET $_suggestions').single.queryParameters;
      expect(query['slot'], 'snack_am');
      expect(query['limit'], 200);
      expect(query['date'], '2026-10-31');
    });

    test('kept for the session; a failed load is not', () async {
      final backend = FakeBackend()
        ..on('GET $_suggestions', 500, {'success': false, 'statusCode': 500});
      final c = await backendContainer(backend);
      final catalog = c.read(recipeCatalogProvider);
      await expectLater(catalog.load(), throwsA(isA<ApiException>()));

      backend
        ..on('GET $_suggestions', 200, fixture('recipe_fixture_swap.json'))
        ..on('GET $_mine', 200, envelope(const <Object>[]));
      expect((await catalog.load()).length, 3);
      await catalog.find(_inCatalog);
      expect(backend.requests('GET $_mine').length, 1);

      catalog.invalidate();
      await catalog.load();
      expect(backend.requests('GET $_mine').length, 2);
    });

    test('merges the tagged slots if the BE stops falling back to all',
        () async {
      final backend = FakeBackend({
        'GET $_suggestions': (r) => (
              200,
              r.queryParameters['slot'] == 'snack_am'
                  ? envelope(const <Object>[])
                  : fixture('recipe_fixture_swap.json')
            ),
      })
        ..on('GET $_mine', 200, envelope(const <Object>[]));
      final c = await backendContainer(backend);
      expect((await c.read(recipeCatalogProvider).load()).length, 3);
      expect(backend.requests('GET $_suggestions').length, 5);
    });

    test('uses the loaded plan\'s id once there is one', () async {
      final backend = FakeBackend()
        ..on('GET /meal-plans/current', 200,
            fixture('planner_fixture_plan.json'))
        ..on('GET /meal-plans/6ae5966f96695f5c139fa9c5/swap-suggestions', 200,
            fixture('recipe_fixture_swap.json'))
        ..on('GET $_mine', 200, envelope(const <Object>[]));
      final c = await backendContainer(backend);
      await c.read(mealPlannerApiProvider).getCurrentMealPlan();
      expect(await c.read(recipeCatalogProvider).load(), hasLength(3));
    });

    test('recipes using an ingredient, by words and without accents', () async {
      final c = await backendContainer(_catalogBackend());
      final catalog = c.read(recipeCatalogProvider);
      final tofu = await catalog.usingIngredient('dau hu');
      expect(tofu.map((r) => r.id), contains(_inCatalog));
      expect(await catalog.usingIngredient('Sầu riêng'), isEmpty);
    });
  });

  group('sameFood', () {
    test('whole words, either way round, without accents', () {
      expect(sameFood('Đậu hũ', 'Đậu hũ non'), isTrue);
      expect(sameFood('đậu hũ non', 'dau hu'), isTrue);
      expect(sameFood('Cà', 'Cà chua'), isTrue);
      expect(sameFood('Cà chua', 'Khoai lang'), isFalse);
    });

    test('short names keep their accents', () {
      expect(sameFood('Bơ', 'Bò'), isFalse);
      expect(sameFood('Bơ', 'Quả bơ'), isTrue);
    });
  });

  group('getRecipe routes by id', () {
    test('a mock id reads the mock store, with no request', () async {
      final backend = FakeBackend();
      final c = await backendContainer(backend);
      final recipe = await c.read(recipeApiProvider).getRecipe('l5');
      expect(recipe.name, isNotEmpty);
      expect(recipe.toEntity().isReadOnly, isFalse);
      expect(backend.seen, isEmpty);
    });

    test('a 24-hex id from the catalogue is a read-only vegan recipe',
        () async {
      final c = await backendContainer(_catalogBackend());
      final recipe =
          (await c.read(recipeApiProvider).getRecipe(_inCatalog)).toEntity();
      expect(recipe.name, 'Cơm gạo lứt đậu hũ kho nấm đông cô');
      expect(recipe.isReadOnly, isTrue);
      expect(recipe.isSnapshot, isFalse);
      expect(recipe.isVegan, isTrue);
      expect(recipe.caloriesCache, 520);
      expect(recipe.proteinG, 26);
      expect(recipe.ingredients.map((i) => i.name), contains('Đậu hũ'));
      expect(recipe.steps, hasLength(3));
      expect(recipe.servings, isNull, reason: 'never made up');
    });

    test('the member\'s own recipe says so', () async {
      final c = await backendContainer(_catalogBackend());
      final mine = (await c
              .read(recipeApiProvider)
              .getRecipe('6ae5962596695f5c139fa9b6'))
          .toEntity();
      expect(mine.createdBy, testUserId);
      expect(mine.isPublic, isFalse);
      expect(mine.ingredients.single.amount, '200 g');
    });

    test('a recipe the catalogue left out falls back to the plan', () async {
      final backend = _catalogBackend()
        ..on('GET /meal-plans/current', 200,
            fixture('planner_fixture_plan.json'));
      backend.on('GET /meal-plans/6ae5966f96695f5c139fa9c5/swap-suggestions',
          200, envelope(const <Object>[]));
      final c = await backendContainer(backend);
      final plan = (await c.read(mealPlannerApiProvider).getCurrentMealPlan())!;
      final id = plan.days.first.meals.values.first.id;

      final page = (await c.read(recipeApiProvider).getRecipe(id)).toEntity();
      expect(page.isSnapshot, isTrue);
      expect(page.name, plan.days.first.meals.values.first.name);
      expect(page.proteinG, isNotNull);
      expect(page.ingredients, isEmpty);
    });

    test('a typed dish is known only through the plan', () async {
      final backend = FakeBackend()
        ..on('POST /meal-plans/current/meals', 200,
            fixture('planner_fixture_add_meal.json'));
      final c = await backendContainer(backend);
      final day = await c.read(mealPlannerApiProvider).addMealToCurrentPlan(
          AddMealRequestDto(
              date: testNow, slot: MealSlot.snackLate, name: 'Canh chua nấm'));
      final typed = day.meals['snack_late']!;
      expect(typed.id, hasLength(32));
      final page =
          (await c.read(recipeApiProvider).getRecipe(typed.id)).toEntity();
      expect(page.isSnapshot, isTrue);
      expect(page.isReadOnly, isTrue);
      expect(page.caloriesCache, 300);
      expect(page.isVegan, isFalse, reason: 'typed in: never claimed');
    });

    test('unknown ids are 404, without asking for the plan-only ones',
        () async {
      final backend = _catalogBackend();
      final c = await backendContainer(backend);
      final api = c.read(recipeApiProvider);
      final is404 = throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', 404));
      await expectLater(
          api.getRecipe('8da78bfdfb3147f0a9d8930ec2354bdc'), is404);
      expect(backend.seen, isEmpty);
      await expectLater(api.getRecipe('6ae595c796695f5c139fffff'), is404);
    });
  });
}
