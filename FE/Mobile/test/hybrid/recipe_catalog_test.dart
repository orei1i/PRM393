// test/hybrid/recipe_catalog_test.dart
// The catalogue a member can read, the plan snapshots and where each kind of id
// goes.
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_api_service.dart';
import 'package:veganlife_mobile/features/recipe/data/recipe_catalog.dart';

import 'planner_test_support.dart';

const _current = '/meal-plans/current';
const _planId = '6ae5966f96695f5c139fa9c5';
const _suggestions = '/meal-plans/$_planId/swap-suggestions';
const _fromFridge = '/meal-plans/from-ingredients';
const _mine = '/users/me/recipes';
const _inCatalog = '6ae595c796695f5c139fa99b';
const _myId = '6ae5962596695f5c139fa9b6';

const _myRow = {
  'id': _myId,
  'name': 'Cơm của tôi',
  'calories': 500,
  'allergens': <String>[],
  'ingredients': ['Cơm 200 g'],
  'instructions': ['Nấu', 'Ăn'],
};

/// A member with a plan this week and one recipe of their own.
FakeBackend _catalogBackend() {
  final rows = fixtureData<List<dynamic>>('recipe_fixture_swap.json')
      .cast<Map<String, dynamic>>();
  return FakeBackend()
    ..on('GET $_current', 200, fixture('planner_fixture_plan.json'))
    ..on('GET $_suggestions', 200, fixture('recipe_fixture_swap.json'))
    ..on('GET $_mine', 200, envelope([_myRow]))
    ..on('GET /recipes/$_myId', 200, envelope(_myRow))
    ..on('GET /recipes/$_inCatalog', 200,
        envelope(rows.firstWhere((r) => r['id'] == _inCatalog)));
}

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
      expect(query['date'], '2000-01-01',
          reason:
              'on a day of the plan the dish in that slot would be missing');
    });

    test('kept for the session; a failed load is not', () async {
      final backend = FakeBackend()
        ..on('GET $_current', 200, fixture('planner_fixture_plan.json'))
        ..on('GET $_suggestions', 500, {'success': false, 'statusCode': 500});
      final c = await backendContainer(backend);
      final catalog = c.read(recipeCatalogProvider);
      await expectLater(catalog.load(), throwsA(isA<ApiException>()));

      backend
        ..on('GET $_suggestions', 200, fixture('recipe_fixture_swap.json'))
        ..on('GET $_mine', 200, envelope(const <Object>[]));
      expect((await catalog.load()).length, 3);
      await catalog.load();
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
        ..on('GET $_current', 200, fixture('planner_fixture_plan.json'))
        ..on('GET $_mine', 200, envelope(const <Object>[]));
      final c = await backendContainer(backend);
      expect((await c.read(recipeCatalogProvider).load()).length, 3);
      expect(backend.requests('GET $_suggestions').length, 5);
    });

    test('a plan the planner loaded is not asked for again', () async {
      final backend = _catalogBackend();
      final c = await backendContainer(backend);
      await c.read(mealPlannerApiProvider).getCurrentMealPlan();
      expect(await c.read(recipeCatalogProvider).load(), hasLength(4));
      expect(backend.requests('GET $_current'), hasLength(1));
    });

    group('no plan this week', () {
      FakeBackend noPlan() => FakeBackend()
        ..on('GET $_current', 404, notFound('Chưa có.'))
        ..on('POST $_fromFridge', 200, fixture('recipe_fixture_swap.json'))
        ..on('GET $_mine', 200, envelope([_myRow]));

      test('what suits the fridge, plus their own; no plan is created',
          () async {
        final backend = noPlan();
        final c = await backendContainer(backend);
        expect(await c.read(recipeCatalogProvider).load(), hasLength(4));
        expect(backend.calls,
            ['GET $_current', 'POST $_fromFridge', 'GET $_mine']);
        expect(backend.requests('POST $_fromFridge').single.data, isNull);
      });

      test('the whole catalogue as soon as there is a plan', () async {
        final backend = noPlan();
        final c = await backendContainer(backend);
        final catalog = c.read(recipeCatalogProvider);
        await catalog.load();
        expect(backend.requests('GET $_suggestions'), isEmpty);

        backend
          ..on('GET $_current', 200, fixture('planner_fixture_plan.json'))
          ..on('GET $_suggestions', 200, fixture('recipe_fixture_swap.json'));
        await c.read(mealPlannerApiProvider).getCurrentMealPlan();
        await catalog.load();
        expect(backend.requests('GET $_suggestions'), hasLength(1));
      });
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

    test('a 24-hex seed recipe is vegan, read by its id, and customizable',
        () async {
      final backend = _catalogBackend();
      final c = await backendContainer(backend);
      final recipe =
          (await c.read(recipeApiProvider).getRecipe(_inCatalog)).toEntity();
      expect(recipe.name, 'Cơm gạo lứt đậu hũ kho nấm đông cô');
      expect(recipe.isFromBackend, isTrue);
      expect(recipe.isReadOnly, isFalse);
      expect(recipe.isSnapshot, isFalse);
      expect(recipe.isVegan, isTrue);
      expect(recipe.caloriesCache, 520, reason: 'the BE figure');
      expect(recipe.proteinG, 26);
      expect(recipe.ingredients.map((i) => i.name), contains('Đậu hũ'));
      expect(recipe.steps, hasLength(3));
      expect(recipe.servings, 2, reason: 'from backend_recipe_items.dart');
      expect(backend.requests('GET $_suggestions'), isEmpty,
          reason: 'a page does not read the catalogue');
    });

    test('the member\'s own recipe says so', () async {
      final c = await backendContainer(_catalogBackend());
      final mine =
          (await c.read(recipeApiProvider).getRecipe(_myId)).toEntity();
      expect(mine.createdBy, testUserId);
      expect(mine.isPublic, isFalse);
      expect(mine.ingredients.single.amount, '200 g');
      expect(mine.isReadOnly, isTrue);
      expect(mine.servings, isNull, reason: 'never made up');
    });

    test('a recipe that cannot be read falls back to the plan', () async {
      final backend = _catalogBackend();
      final c = await backendContainer(backend);
      final plan = (await c.read(mealPlannerApiProvider).getCurrentMealPlan())!;
      final id = plan.days.first.meals.values.first.id;
      backend.on('GET /recipes/$id', 404, notFound('Không tìm thấy công thức'));

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
      backend.on('GET /recipes/6ae595c796695f5c139fffff', 404,
          notFound('Không tìm thấy công thức'));
      await expectLater(api.getRecipe('6ae595c796695f5c139fffff'), is404);
    });
  });
}
