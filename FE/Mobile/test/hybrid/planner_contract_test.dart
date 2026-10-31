// test/hybrid/planner_contract_test.dart
// The planner against recorded BE answers: allergens, slot ids, the profile
// and metrics workarounds, and which route each dish takes (D10).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/core/config/backend_modules.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/features/meal_planner/data/allergen_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock/mock_recipe_book.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/body_measurement_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/body_metrics_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';

import 'planner_test_support.dart';

const _plan = '/meal-plans/current';
const _profile = '/health-profile/me';
const _metrics = '/health-profile/me/metrics';
const _meals = '/meal-plans/current/meals';
const _planId = '6ae5966f96695f5c139fa9c5';
const _patch = '/meal-plans/$_planId/meals';
const _realRecipe = '6ae595c796695f5c139fa9a1';
const _typedDish = '8da78bfdfb3147f0a9d8930ec2354bdc';

Map<String, dynamic> _item(Map<String, dynamic> over) => {
      'id': _typedDish,
      'recipeId': null,
      'name': 'Canh chua',
      'calories': 300,
      'proteinG': null,
      'carbsG': null,
      'fatG': null,
      'fiberG': null,
      'allergens': <String>[],
      'dietTags': <String>[],
      'prepMinutes': 15,
      'imageUrl': null,
      'source': 'manual',
      'sourceName': null,
      'portion': 1,
      'seasonalSwap': null,
      'allergyConflicts': <String>[],
      ...over,
    };

Recipe _recipe(String id, {MealSource source = MealSource.recipe}) => Recipe(
    id: id,
    name: 'Món $id',
    nutrition: const Nutrition(calories: 400, proteinG: 12),
    source: source);

/// The recorded week, with the day of [testNow] selected.
FakeBackend _plannerBackend() => FakeBackend()
  ..on('GET $_profile', 200, fixture('planner_fixture_profile.json'))
  ..on('GET $_plan', 200, fixture('planner_fixture_plan.json'))
  ..on('PATCH $_patch', 200, fixture('planner_fixture_patch.json'))
  ..on('POST $_meals', 200, fixture('planner_fixture_add_meal.json'));

void main() {
  setUp(() {
    BackendModules.debugOverride(BackendModules.supportedByBackend);
    MockRecipeBook.reset();
  });
  tearDown(() => BackendModules.debugOverride(null));

  group('allergens (safety)', () {
    test('a catalog pick is the allergen id, not the label as free text',
        () async {
      final backend = FakeBackend()
        ..on('GET /catalog/allergens', 200,
            fixture('planner_fixture_allergens.json'))
        ..on('GET $_profile', 200, fixture('planner_fixture_profile.json'))
        ..on('PUT $_profile', 200, fixture('planner_fixture_profile.json'));
      final c = await backendContainer(backend);

      final picks = await c.read(allergenApiProvider).search('Đậu phộng');
      expect(picks.single.id, 'peanut');
      expect(picks.single.key, 'peanut');

      await c.read(mealPlannerApiProvider).updateHealthProfile(
          UpdateHealthProfileRequestDto(
              heightCm: 170,
              weightKg: 60,
              goal: HealthGoal.maintain,
              allergies: [picks.single.key],
              dietaryRestrictions: const []));
      final allergies = backend.bodyOf('PUT $_profile')['allergies'] as List;
      expect((allergies.single as Map)['allergenId'], 'peanut');
    });

    test('the words inside the BE label find the allergen; the search is local',
        () async {
      final backend = FakeBackend()
        ..on('GET /catalog/allergens', 200,
            fixture('planner_fixture_allergens.json'));
      final api = (await backendContainer(backend)).read(allergenApiProvider);

      for (final (query, id) in [
        ('lạc', 'peanut'),
        ('dau phong', 'peanut'),
        ('vung', 'sesame'),
        ('hạnh nhân', 'tree_nut'),
      ]) {
        final hits = await api.search(query);
        expect(hits.map((a) => a.id), contains(id), reason: query);
      }
      final lac = (await api.search('lạc')).single;
      expect(lac.isNamed('lạc'), isTrue, reason: 'Enter on "lạc" picks it');
      expect((await api.search('', limit: 3)).length, 3);
      expect(await api.search('zzz'), isEmpty);
      expect(backend.requests('GET /catalog/allergens').length, 1);
      expect(backend.seen.single.queryParameters, isEmpty,
          reason: 'the BE ignores q and limit');
    });

    test('allergy keys read back from the recorded profile', () async {
      final dto = HealthProfileDto.fromJson(
          fixtureData<Map<String, dynamic>>('planner_fixture_profile.json'));
      expect(dto.allergies, ['peanut', 'lá lốt']);
      expect(dto.targetCalories, 2060);
      expect(dto.toEntity().dailyKcalTarget, 2060);
    });
  });

  group('meal slots', () {
    test('a recipe in a slot opens by recipeId and keeps its page', () {
      final swapped = RecipeDto.fromJson(_item(
              {'recipeId': _realRecipe, 'source': 'manual', 'proteinG': 26}))
          .toEntity();
      expect(swapped.id, _realRecipe);
      expect(swapped.source, MealSource.recipe);
      expect(swapped.hasDetail, isTrue);
      expect(swapped.nutrition.proteinG, 26);
    });

    test('a typed dish keeps its slot id, no page and unknown macros', () {
      final typed = RecipeDto.fromJson(_item({})).toEntity();
      expect(typed.id, _typedDish);
      expect(typed.source, MealSource.manual);
      expect(typed.hasDetail, isFalse);
      expect(typed.nutrition.proteinG, isNull);
    });

    test('a mock payload is read as before', () {
      final mock = RecipeDto.fromJson(
          {'id': 'l5', 'name': 'Bún', 'calories': 500, 'source': 'manual'});
      expect(mock.id, 'l5');
      expect(mock.source, 'manual');
      expect(mock.toJson().containsKey('allergyConflicts'), isFalse);
    });

    test('the server\'s allergy conflicts add to the local check', () {
      final dish = RecipeDto.fromJson(_item({
        'name': 'Gỏi cuốn',
        'allergens': ['soy'],
        'allergyConflicts': ['soy', 'lá lốt'],
      })).toEntity();
      expect(dish.allergenConflicts(['soy', 'lá lốt']), ['soy', 'lá lốt']);
      expect(
          dish.withSource(MealSource.chef).serverConflicts, ['soy', 'lá lốt']);
    });

    test('the recorded plan parses, extra slots included', () async {
      final c = await backendContainer(_plannerBackend());
      final plan = (await c.read(mealPlannerApiProvider).getCurrentMealPlan())!;
      expect(plan.id, _planId);
      expect(plan.days.length, 7);
      final today = plan.toEntity().dayFor(testNow)!;
      expect(today.meals[MealSlot.breakfast]!.id, hasLength(24));
    });

    test('a plan of another week reads as no plan', () async {
      final old = fixture('planner_fixture_plan.json');
      (old['data'] as Map)['startDate'] = '2026-10-19';
      final backend = FakeBackend()..on('GET $_plan', 200, old);
      final c = await backendContainer(backend);
      expect(await c.read(mealPlannerApiProvider).getCurrentMealPlan(), isNull);
    });

    test('404 reads as no plan', () async {
      final backend = FakeBackend()
        ..on('GET $_plan', 404, notFound('Bạn chưa có thực đơn cho tuần này.'));
      final c = await backendContainer(backend);
      expect(await c.read(mealPlannerApiProvider).getCurrentMealPlan(), isNull);
    });
  });

  group('which route a dish takes (D10)', () {
    Future<(FakeBackend, ProviderContainer, MealPlanController)> ready() async {
      final backend = _plannerBackend();
      final c = await backendContainer(backend);
      await c.read(mealPlanControllerProvider.future);
      return (backend, c, c.read(mealPlanControllerProvider.notifier));
    }

    test('a real recipe goes by PATCH, by its recipe id', () async {
      final (backend, _, planner) = await ready();
      await planner.swapMeal(MealSlot.lunch, _recipe(_realRecipe));
      expect(backend.bodyOf('PATCH $_patch')['recipeId'], _realRecipe);
      expect(backend.requests('POST $_meals'), isEmpty);
    });

    test('a mock recipe goes by POST, its id as sourceId', () async {
      final (backend, _, planner) = await ready();
      await planner.swapMeal(MealSlot.lunch, _recipe('l5'));
      expect(backend.requests('PATCH $_patch'), isEmpty);
      final body = backend.bodyOf('POST $_meals');
      expect(body['sourceId'], 'l5');
      expect(body['source'], 'recipe');
      expect(body['name'], 'Món l5');
      expect(body['calories'], 400);
    });

    test('a typed dish goes by POST without an id', () async {
      final (backend, _, planner) = await ready();
      await planner.swapMeal(
          MealSlot.lunch, _recipe(_typedDish, source: MealSource.manual));
      final body = backend.bodyOf('POST $_meals');
      expect(body.containsKey('sourceId'), isFalse);
      expect(body['source'], 'manual');
    });

    test('undo puts back the replaced dish by its own route', () async {
      final (backend, _, planner) = await ready();
      final added = AddedMeal(
        date: testNow,
        slot: MealSlot.lunch,
        recipe: _recipe(_realRecipe),
        replaced: _recipe(_typedDish, source: MealSource.manual),
      );
      await planner.undoAddMeal(added);
      expect(backend.requests('POST $_meals').length, 1);

      await planner.undoAddMeal(AddedMeal(
        date: testNow,
        slot: MealSlot.lunch,
        recipe: _recipe(_typedDish),
        replaced: _recipe(_realRecipe),
      ));
      expect(backend.requests('PATCH $_patch').length, 1);
    });

    test('a scan suggestion from the catalogue goes by PATCH, keeping macros',
        () async {
      final (backend, _, planner) = await ready();
      await planner.addMealToToday(
          slot: MealSlot.lunch,
          name: 'Cơm',
          calories: 500,
          sourceId: _realRecipe);
      expect(backend.bodyOf('PATCH $_patch')['recipeId'], _realRecipe);
      expect(backend.requests('POST $_meals'), isEmpty);
    });

    test('a failed POST rolls the slot back', () async {
      final (backend, c, planner) = await ready();
      backend.on('POST $_meals', 500, {'success': false, 'statusCode': 500});
      final before = c
          .read(mealPlanControllerProvider)
          .requireValue
          .selectedDay!
          .meals[MealSlot.lunch];
      await expectLater(planner.swapMeal(MealSlot.lunch, _recipe('l5')),
          throwsA(isA<ApiException>()));
      expect(
          c
              .read(mealPlanControllerProvider)
              .requireValue
              .selectedDay!
              .meals[MealSlot.lunch]
              ?.id,
          before?.id);
    });
  });

  group('health profile', () {
    const request = UpdateHealthProfileRequestDto(
      heightCm: 170,
      weightKg: 60,
      goal: HealthGoal.loseWeight,
      allergies: ['peanut', 'lá lốt'],
      dietaryRestrictions: [],
      gender: Gender.male,
      birthYear: 2000,
      activityLevel: ActivityLevel.moderate,
      mealPattern: [MealSlot.lunch],
    );

    test('goals use the short values the BE adjusts for', () {
      expect(request.toBackendJson()['goal'], 'lose');
      expect(
          const UpdateHealthProfileRequestDto(
              heightCm: 1,
              weightKg: 1,
              goal: HealthGoal.gainWeight,
              allergies: [],
              dietaryRestrictions: []).toBackendJson()['goal'],
          'gain');
      expect(request.toJson()['goal'], 'lose_weight',
          reason: 'the mock keeps its own values');
    });

    test('nothing is lost: missing fields come from the saved profile',
        () async {
      final backend = FakeBackend()
        ..on('GET $_profile', 200, fixture('planner_fixture_profile.json'))
        ..on('PUT $_profile', 200, fixture('planner_fixture_profile.json'));
      final c = await backendContainer(backend);
      final saved = await c.read(mealPlannerApiProvider).updateHealthProfile(
          const UpdateHealthProfileRequestDto(
              heightCm: 170,
              weightKg: 60,
              goal: HealthGoal.maintain,
              allergies: [],
              dietaryRestrictions: []));
      final body = backend.bodyOf('PUT $_profile');
      expect(body['gender'], 'Female');
      expect(body['birthYear'], 1997);
      expect(body['activityLevel'], 'light');
      expect(body['mealPattern'], ['breakfast', 'lunch', 'snack_pm', 'dinner']);
      expect(saved.targetCalories, 2060);
    });

    test('with every field given nothing is read first', () async {
      final backend = FakeBackend()
        ..on('PUT $_profile', 200, fixture('planner_fixture_profile.json'));
      final c = await backendContainer(backend);
      await c.read(mealPlannerApiProvider).updateHealthProfile(request);
      expect(backend.calls, ['PUT $_profile']);
      expect(backend.bodyOf('PUT $_profile')['gender'], 'Male');
    });

    test('a first profile leaves them out instead of sending null', () async {
      final backend = FakeBackend()
        ..on('GET $_profile', 404, notFound('Bạn chưa tạo hồ sơ sức khỏe.'))
        ..on('PUT $_profile', 200, fixture('planner_fixture_profile.json'));
      final c = await backendContainer(backend);
      await c.read(mealPlannerApiProvider).updateHealthProfile(
          const UpdateHealthProfileRequestDto(
              heightCm: 170,
              weightKg: 60,
              goal: HealthGoal.maintain,
              allergies: [],
              dietaryRestrictions: []));
      final body = backend.bodyOf('PUT $_profile');
      expect(body.containsKey('gender'), isFalse);
      expect(body.containsKey('birthYear'), isFalse);
    });
  });

  group('the week follows the profile target', () {
    Map<String, dynamic> profileWithTarget(int target) {
      final json = fixture('planner_fixture_profile.json');
      (json['data'] as Map)['targetCalories'] = target;
      return json;
    }

    test('on load, with the BE\'s macro split', () async {
      final backend = _plannerBackend()
        ..on('GET $_profile', 200, profileWithTarget(1660));
      final c = await backendContainer(backend);
      final plan = (await c.read(mealPlanControllerProvider.future)).plan!;
      expect(plan.dailyTargets.calories, 1660);
      expect(plan.dailyTargets.proteinG, 62.3);
      expect(plan.dailyTargets.carbsG, 228.3);
      expect(plan.dailyTargets.fatG, 55.3);
      expect(plan.dailyTargets.fiberG, 30);
    });

    test('the recorded target needs no change', () async {
      final c = await backendContainer(_plannerBackend());
      final plan = (await c.read(mealPlanControllerProvider.future)).plan!;
      expect(plan.dailyTargets.proteinG, 77.2, reason: 'as the BE sent it');
    });
  });

  group('weigh-ins without a POST', () {
    FakeBackend backendWith(List<Map<String, dynamic>> metricsAnswers) {
      var i = 0;
      return FakeBackend({
        'GET $_metrics': (_) => (
              200,
              envelope(
                  [metricsAnswers[i < metricsAnswers.length ? i++ : i - 1]])
            ),
      })
        ..on('GET $_profile', 200, fixture('planner_fixture_profile.json'))
        ..on('PUT $_profile', 200, fixture('planner_fixture_profile.json'));
    }

    Map<String, dynamic> row(String id, double kg, String at) => {
          'id': id,
          'weightKg': kg,
          'heightCm': 172,
          'bmi': 22.3,
          'loggedAt': at,
        };

    final Map<String, dynamic> oldRow =
        row('m1', 66, '2026-10-30T07:19:11.062Z');

    test('a new weight returns the row the BE logged', () async {
      final fresh = row('m2', 64.2, '2026-10-31T07:19:11.062Z');
      final backend = backendWith([oldRow, fresh]);
      final c = await backendContainer(backend);
      final result = await c
          .read(mealPlannerApiProvider)
          .logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 64.2));
      expect(result.measurement.id, 'm2');
      expect(backend.calls.where((p) => p.startsWith('POST')), isEmpty);
      final body = backend.bodyOf('PUT $_profile');
      expect(body['weightKg'], 64.2);
      expect(body['heightCm'], 172);
      expect(body['birthYear'], 1997);
      expect((body['allergies'] as List).length, 2);
    });

    test('the same weight logs nothing: a row that is not kept', () async {
      final backend = backendWith([oldRow, oldRow]);
      final c = await backendContainer(backend);
      final result = await c
          .read(mealPlannerApiProvider)
          .logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 66));
      expect(result.measurement.id, startsWith('local_'));
      expect(result.measurement.toEntity().isLocalOnly, isTrue);
      expect(result.measurement.loggedAt, testNow);
    });

    test('the controller keeps a local row out of the history', () async {
      final backend = backendWith([oldRow, oldRow, oldRow]);
      final c = await backendContainer(backend);
      await c.read(bodyMeasurementsProvider.future);
      final result =
          await c.read(bodyMeasurementsProvider.notifier).log(weightKg: 66);
      expect(result.measurement.isLocalOnly, isTrue);
      expect(c.read(bodyMeasurementsProvider).requireValue.map((m) => m.id),
          ['m1']);
    });

    test('without a profile: the usual message', () async {
      final backend = FakeBackend()
        ..on('GET $_profile', 404, notFound('Bạn chưa tạo hồ sơ sức khỏe.'));
      final c = await backendContainer(backend);
      await expectLater(
          c
              .read(mealPlannerApiProvider)
              .logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 60)),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'status', 404)
              .having((e) => e.message, 'message',
                  'Bạn chưa tạo hồ sơ sức khỏe.')));
    });

    test('recorded rows: no source, and the pill stays off', () async {
      final rows = fixtureData<List<dynamic>>('planner_fixture_metrics.json')
          .cast<Map<String, dynamic>>();
      final parsed = rows.map(BodyMeasurementDto.fromJson).toList();
      expect(parsed.first.weightKg, 66);
      expect(parsed.first.source, isNull);
    });
  });

  group('own recipes and chef dishes', () {
    test('POST /recipes takes text rows and steps; the result is the member\'s',
        () async {
      final backend = FakeBackend()
        ..on(
            'POST /recipes',
            201,
            envelope({
              'id': _realRecipe,
              'name': 'Cơm',
              'calories': 500,
              'proteinG': null,
              'allergens': <String>[],
              'dietTags': <String>[],
              'prepMinutes': 15,
              'ingredients': ['Đậu hũ 200 g', 'Cà chua'],
              'instructions': ['Nấu', 'Ăn'],
            }));
      final c = await backendContainer(backend);
      final recipe = await c
          .read(mealPlannerApiProvider)
          .createMyRecipe(const CreateRecipeRequestDto(
            name: 'Cơm',
            calories: 500,
            proteinG: 10,
            prepMinutes: 20,
            servings: 2,
            ingredients: [
              RecipeIngredientInput(name: 'Đậu hũ', quantity: 200, unit: 'g'),
              RecipeIngredientInput(name: 'Cà chua', quantity: 0, unit: ''),
              RecipeIngredientInput(name: 'Nước', quantity: 1.5, unit: 'lít'),
            ],
            steps: [' Nấu ', 'Ăn'],
          ));
      final body = backend.bodyOf('POST /recipes');
      expect(body['calories'], 500);
      expect(body['ingredients'], ['Đậu hũ 200 g', 'Cà chua', 'Nước 1.5 lít']);
      expect(body['instructions'], ['Nấu', 'Ăn']);
      expect(body.containsKey('caloriesCache'), isFalse);
      expect(recipe.createdBy, testUserId);
      expect(recipe.source, 'user_recipe');
    });

    test('"Công thức của tôi": real ones plus variants of mock recipes',
        () async {
      MockRecipeBook.addUserRecipe(
          userId: 'u_me',
          userName: 'Minh Anh',
          recipe: {'name': 'Biến thể', 'caloriesCache': 300});
      final backend = FakeBackend()
        ..on(
            'GET /users/me/recipes',
            200,
            envelope([
              {'id': _realRecipe, 'name': 'Cơm', 'calories': 500},
            ]));
      final c = await backendContainer(backend);
      final mine = await c.read(mealPlannerApiProvider).getMyRecipes();
      expect(mine.map((r) => r.name), ['Biến thể', 'Cơm']);
      expect(mine.last.createdBy, testUserId);
      expect(mine.every((r) => r.source == 'user_recipe'), isTrue);
    });

    test('"Từ chuyên gia" reads the mock store while bookings are mock',
        () async {
      final backend = FakeBackend();
      final c = await backendContainer(backend);
      final dishes = await c.read(mealPlannerApiProvider).getChefSuggestions();
      expect(dishes, isNotEmpty);
      expect(backend.seen, isEmpty);
    });

    test('a guest has none, without a request', () async {
      final backend = FakeBackend();
      final c = await backendContainer(backend, signedIn: false);
      expect(
          await c.read(mealPlannerApiProvider).getChefSuggestions(), isEmpty);
      expect(backend.seen, isEmpty);
    });
  });

  test('the persona only applies with real auth', () async {
    final c = await backendContainer(FakeBackend());
    expect(c.read(plannerPersonaIdProvider), 'u_me');

    BackendModules.debugOverride({BackendModule.planner});
    final c2 = await backendContainer(FakeBackend());
    expect(c2.read(plannerPersonaIdProvider), testUserId);
  });

  test('mock provider when the module is mock', () async {
    BackendModules.debugOverride(const {});
    final c = await backendContainer(FakeBackend());
    expect(c.read(mealPlannerApiProvider),
        isNot(isA<RemoteMealPlannerApiService>()));
  });
}
