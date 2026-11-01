// test/hybrid/planner_contract_test.dart
// The planner against recorded BE answers: allergens, slot ids, portions, the
// profile, weigh-ins, and which route each dish takes (D10).
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
import 'package:veganlife_mobile/features/meal_planner/domain/allergy_match.dart';
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
          reason: 'the app searches the whole list itself');
    });

    test('an allergy saved as a name still conflicts with the tagged allergen',
        () {
      for (final name in ['Đậu nành', 'dau nanh', 'Đậu nành (Đậu tương)']) {
        expect(
            allergyConflicts(
                tags: const ['soy'],
                texts: const ['Bún riêu chay đậu hũ'],
                userAllergies: [name]),
            ['soy'],
            reason: name);
      }
      // Still read in the words of an untagged dish, and only once.
      expect(
          allergyConflicts(
              tags: const [],
              texts: const ['Sữa đậu nành'],
              userAllergies: const ['Đậu nành']),
          ['Đậu nành']);
      // Any other typed name is not an allergen id.
      expect(dishAllergenIdNamed('lá lốt'), isNull);
      expect(
          allergyConflicts(
              tags: const ['soy'],
              texts: const ['Đậu hũ'],
              userAllergies: const ['lá lốt']),
          isEmpty);
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
              {'recipeId': _realRecipe, 'source': 'recipe', 'proteinG': 26}))
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

    test('the portions of a generated week count (B31)', () async {
      final json = fixture('planner_fixture_plan.json');
      final today = ((json['data'] as Map)['days'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((d) => d['date'] == '2026-10-31');
      final lunch = (today['meals'] as Map)['lunch'] as Map<String, dynamic>;
      final perServing = lunch['calories'] as num;
      lunch
        ..['portion'] = 1.5
        ..['proteinG'] = 10;
      final backend = FakeBackend()..on('GET $_plan', 200, json);
      final c = await backendContainer(backend);

      final plan = (await c.read(mealPlannerApiProvider).getCurrentMealPlan())!;
      final dish = plan.toEntity().dayFor(testNow)!.meals[MealSlot.lunch]!;
      expect(dish.portion, 1.5);
      expect(dish.nutrition.calories, (perServing * 1.5).round());
      expect(dish.nutrition.proteinG, 15);
    });

    test('a suggestion comes at the portion the slot was sized to', () async {
      final json = fixture('planner_fixture_plan.json');
      final today = ((json['data'] as Map)['days'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((d) => d['date'] == '2026-10-31');
      ((today['meals'] as Map)['lunch'] as Map)['portion'] = 1.5;
      final backend = _plannerBackend()
        ..on('GET $_plan', 200, json)
        ..on(
            'GET /meal-plans/$_planId/swap-suggestions',
            200,
            envelope([
              {'id': _realRecipe, 'name': 'Món khác', 'calories': 400},
            ]));
      final c = await backendContainer(backend);
      await c.read(mealPlanControllerProvider.future);
      final planner = c.read(mealPlanControllerProvider.notifier);

      final choice =
          (await planner.fetchSwapSuggestions(MealSlot.lunch)).single;
      expect(choice.portion, 1.5);
      expect(choice.nutrition.calories, 600);

      await planner.swapMeal(MealSlot.lunch, choice);
      expect(backend.bodyOf('PATCH $_patch')['portion'], 1.5);
    });

    test('a swap at a portion answers per serving too (B6)', () async {
      final backend = _plannerBackend();
      final json = fixture('planner_fixture_patch.json');
      final day = json['data'] as Map;
      final lunch = (day['meals'] as Map)['lunch'] as Map<String, dynamic>;
      final perServing = lunch['calories'] as num;
      lunch['portion'] = 1.5;
      backend.on('PATCH $_patch', 200, json);
      final c = await backendContainer(backend);
      await c.read(mealPlanControllerProvider.future);
      await c
          .read(mealPlanControllerProvider.notifier)
          .swapMeal(MealSlot.lunch, _recipe(_realRecipe));
      final dish = c
          .read(mealPlanControllerProvider)
          .requireValue
          .selectedDay!
          .meals[MealSlot.lunch]!;
      expect(dish.nutrition.calories, (perServing * 1.5).round());
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

    test('a typed dish sends all its macros (B7)', () async {
      final (backend, _, planner) = await ready();
      await planner.addManualMeal(
          slot: MealSlot.lunch,
          name: 'Canh chua',
          calories: 200,
          proteinG: 10,
          carbsG: 20,
          fatG: 5);
      final body = backend.bodyOf('POST $_meals');
      expect(body['proteinG'], 10);
      expect(body['carbsG'], 20);
      expect(body['fatG'], 5);
    });

    test('"Áp dụng kế hoạch" with no plan this week says what to do', () async {
      final backend = FakeBackend()
        ..on('GET $_profile', 200, fixture('planner_fixture_profile.json'))
        ..on('GET $_plan', 404, notFound('Bạn chưa có thực đơn cho tuần này.'));
      final c = await backendContainer(backend);
      await c.read(mealPlanControllerProvider.future);
      await expectLater(
        c.read(mealPlanControllerProvider.notifier).addMeals([
          AddMealRequestDto(date: testNow, slot: MealSlot.lunch, name: 'Món'),
        ]),
        throwsA(isA<ApiException>().having((e) => e.message, 'message',
            contains('Vào tab Thực đơn để tạo trước'))),
      );
      expect(backend.calls.where((p) => p.startsWith('POST')), isEmpty);
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

    test('goals go as the whitelist of the BE: no short values', () {
      for (final goal in HealthGoal.values) {
        expect(
            UpdateHealthProfileRequestDto(
                heightCm: 1,
                weightKg: 1,
                goal: goal,
                allergies: const [],
                dietaryRestrictions: const []).toBackendJson()['goal'],
            isIn(const [
              'lose_weight',
              'maintain',
              'lean_muscle',
              'gain_weight'
            ]));
      }
      expect(request.toBackendJson()['goal'], 'lose_weight');
    });

    test('older goals, and the ones with no choice here, still read', () {
      expect(HealthGoal.fromApi('lose'), HealthGoal.loseWeight);
      expect(HealthGoal.fromApi('gain'), HealthGoal.gainWeight);
      expect(HealthGoal.fromApi('lose_weight'), HealthGoal.loseWeight);
      expect(HealthGoal.fromApi('gain_weight'), HealthGoal.gainWeight);
      expect(HealthGoal.fromApi('gain_muscle'), HealthGoal.leanMuscle);
      expect(HealthGoal.fromApi('eat_clean'), HealthGoal.maintain);
    });

    test('a missing activity level comes from the saved profile (B9)',
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
      expect(body['activityLevel'], 'light');
      expect(body.containsKey('gender'), isFalse, reason: 'the BE keeps it');
      expect(body.containsKey('birthYear'), isFalse, reason: 'the BE keeps it');
      expect(body.containsKey('mealPattern'), isFalse,
          reason: 'the BE keeps it');
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

  group('the week shows what the BE aims it at (B8)', () {
    test('its targets, even with another one on the profile', () async {
      final profile = fixture('planner_fixture_profile.json');
      (profile['data'] as Map)['targetCalories'] = 1660;
      final backend = _plannerBackend()..on('GET $_profile', 200, profile);
      final c = await backendContainer(backend);
      final plan = (await c.read(mealPlanControllerProvider.future)).plan!;
      expect(plan.dailyTargets.calories, 2060);
      expect(plan.dailyTargets.proteinG, 77.2);
    });

    test('a saved profile reads the week again', () async {
      final backend = _plannerBackend()
        ..on('PUT $_profile', 200, fixture('planner_fixture_profile.json'));
      final c = await backendContainer(backend);
      final state = await c.read(mealPlanControllerProvider.future);
      final fresh = fixture('planner_fixture_plan.json');
      ((fresh['data'] as Map)['dailyTargets'] as Map)['calories'] = 1660;
      backend.on('GET $_plan', 200, fresh);

      await c.read(mealPlanControllerProvider.notifier).updateHealthProfile(
            heightCm: 170,
            weightKg: 60,
            goal: HealthGoal.loseWeight,
            allergies: const [],
            dietaryRestrictions: const [],
            mealPattern: state.pattern,
          );
      await pumpEventQueue();
      expect(
          c
              .read(mealPlanControllerProvider)
              .requireValue
              .plan!
              .dailyTargets
              .calories,
          1660);
    });
  });

  group('weigh-ins', () {
    const logged = {
      'id': 'm2',
      'weightKg': 64.2,
      'heightCm': 172,
      'bmi': 21.7,
      'waistCm': 75.5,
      'bodyFatPct': 18.2,
      'loggedAt': '2026-10-31T07:19:11.062Z',
    };

    FakeBackend backend() => FakeBackend()
      ..on('GET $_profile', 200, fixture('planner_fixture_profile.json'))
      ..on('POST $_metrics', 201, envelope(logged))
      ..on('PUT $_profile', 200, fixture('planner_fixture_profile.json'))
      ..on('GET $_metrics', 200, envelope([logged]));

    test('POST the row, then PUT the profile so its target follows (B37)',
        () async {
      final b = backend();
      final c = await backendContainer(b);
      final result = await c
          .read(mealPlannerApiProvider)
          .logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 64.2));

      expect(b.calls, ['GET $_profile', 'POST $_metrics', 'PUT $_profile']);
      expect(b.bodyOf('POST $_metrics'), {'weightKg': 64.2});
      final put = b.bodyOf('PUT $_profile');
      expect(put['weightKg'], 64.2);
      expect(put['heightCm'], 172);
      expect(put['activityLevel'], 'light');
      expect((put['allergies'] as List).length, 2);
      expect(result.measurement.id, 'm2');
      expect(result.profile.targetCalories, 2060);
    });

    test('the row counts even if the PUT after it fails', () async {
      final b = backend()..on('PUT $_profile', 500, {'statusCode': 500});
      final c = await backendContainer(b);
      final result = await c
          .read(mealPlannerApiProvider)
          .logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 64.2));
      expect(result.measurement.id, 'm2');
      expect(result.profile.heightCm, 172);
    });

    test('what the BE would store blindly is refused first (B36)', () async {
      for (final bad in const [
        LogMeasurementRequestDto(weightKg: -5),
        LogMeasurementRequestDto(weightKg: 0),
        LogMeasurementRequestDto(weightKg: 251),
      ]) {
        final b = backend();
        final c = await backendContainer(b);
        await expectLater(
          c.read(mealPlannerApiProvider).logBodyMeasurement(bad),
          throwsA(isA<ApiException>()
              .having((e) => e.statusCode, 'status', 400)
              .having((e) => e.code, 'code', 'invalid_measurement')),
        );
        expect(b.seen, isEmpty, reason: 'nothing is sent: ${bad.toJson()}');
      }
    });

    test('the controller puts it on top of the history', () async {
      final c = await backendContainer(backend());
      await c.read(bodyMeasurementsProvider.future);
      final result =
          await c.read(bodyMeasurementsProvider.notifier).log(weightKg: 64.2);
      expect(result.measurement.id, 'm2');
      expect(c.read(bodyMeasurementsProvider).requireValue.first.id, 'm2');
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
      expect(backend.calls, ['GET $_profile'], reason: 'no row is made up');
    });

    test('old rows with waist and body fat still parse; no source', () async {
      final rows = fixtureData<List<dynamic>>('planner_fixture_metrics.json')
          .cast<Map<String, dynamic>>();
      final parsed = rows.map(BodyMeasurementDto.fromJson).toList();
      expect(parsed.first.weightKg, 66);
      expect(parsed.first.source, isNull);
      final old = BodyMeasurementDto.fromJson(logged);
      expect(old.bmi, 21.7);
      expect(old.toEntity().weightKg, 64.2);
      expect(old.toJson().containsKey('waistCm'), isFalse);
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
