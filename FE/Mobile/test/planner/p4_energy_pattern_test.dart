// test/planner/p4_energy_pattern_test.dart
//
// P4 (TestPRM p18): energy need from the health profile (Mifflin–St Jeor),
// the meals of the day ("Các bữa trong ngày") and extra meals for one day,
// free-text allergies.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veganlife_mobile/core/network/api_exception.dart';
import 'package:veganlife_mobile/core/session/session_controller.dart';
import 'package:veganlife_mobile/core/utils/energy.dart';
import 'package:veganlife_mobile/core/utils/formatters.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock/meal_planner_mock_data.dart';
import 'package:veganlife_mobile/features/meal_planner/data/mock_meal_planner_repository.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/meal_plan_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/allergy_match.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/controllers/meal_plan_controller.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/health_profile_edit_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/screens/meal_planner_screen.dart';
import 'package:veganlife_mobile/features/meal_planner/presentation/widgets/meal_picker_sheet.dart';

const _minhAnh = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Minh Anh',
  'vl.user_id': 'u_me',
  'vl.role': 'User',
};

const _tam = {
  'vl.access_token': 'mock.jwt',
  'vl.display_name': 'Lê Quang Tâm',
  'vl.user_id': 'u_chef_tam',
  'vl.role': 'Chef',
};

/// A Wednesday: the mock week is Mon 12/10 → Sun 18/10.
final _wed = DateTime(2026, 10, 14, 9);

Matcher _apiError(int status) =>
    throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', status));

Future<SharedPreferences> _prefs(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<ProviderContainer> _container(
    [Map<String, Object> session = _minhAnh]) async {
  final prefs = await _prefs(session);
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    plannerClockProvider.overrideWithValue(() => _wed),
  ]);
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(WidgetTester tester, Widget home,
    {Map<String, Object> session = _minhAnh,
    Size size = const Size(411, 1600)}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final prefs = await _prefs(session);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      plannerClockProvider.overrideWithValue(() => _wed),
    ],
    child: MaterialApp(home: home),
  ));
}

Future<void> _wait(WidgetTester tester, [int ms = 2000]) async {
  for (var t = 0; t < ms; t += 250) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

UpdateHealthProfileRequestDto _request({
  List<String> allergies = const ['peanut'],
  List<MealSlot>? pattern,
  int? birthYear,
}) =>
    UpdateHealthProfileRequestDto(
      heightCm: 172,
      weightKg: 66,
      goal: HealthGoal.leanMuscle,
      allergies: allergies,
      dietaryRestrictions: const [],
      mealPattern: pattern,
      birthYear: birthYear,
    );

int _kcal(MealPlanDayDto day) =>
    day.meals.values.fold(0, (sum, r) => sum + r.nutrition.calories);

/// The mock planner, counting add-meal round trips.
class _CountingPlanner extends MockMealPlannerRepository {
  _CountingPlanner() : super(userId: 'u_me', clock: () => _wed);

  int singleCalls = 0;
  int batchCalls = 0;

  @override
  Future<MealPlanDayDto> addMealToCurrentPlan(AddMealRequestDto request) {
    singleCalls++;
    return super.addMealToCurrentPlan(request);
  }

  @override
  Future<AddMealsResultDto> addMealsToCurrentPlan(
      List<AddMealRequestDto> requests) {
    batchCalls++;
    return super.addMealsToCurrentPlan(requests);
  }
}

void main() {
  setUpAll(() async {
    final dir =
        '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
    final roboto = FontLoader('Roboto');
    for (final weight in ['regular', 'medium', 'bold']) {
      final file = File('$dir/roboto-$weight.ttf');
      if (file.existsSync()) {
        roboto.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await roboto.load();
  });

  setUp(MockMealPlannerRepository.reset);

  group('BMR / TDEE (Mifflin–St Jeor)', () {
    test('male, female and "Khác" (mean of the two constants)', () {
      double bmr(Gender g) =>
          Energy.bmr(gender: g, weightKg: 70, heightCm: 175, age: 30);
      expect(bmr(Gender.male), 1648.75);
      expect(bmr(Gender.female), 1482.75);
      expect(bmr(Gender.other), 1565.75);
      expect(bmr(Gender.other), (bmr(Gender.male) + bmr(Gender.female)) / 2);
    });

    test('activity factors and goal adjustment −15 % / 0 / +5 % / +10 %', () {
      expect(Energy.tdee(1000, ActivityLevel.sedentary), 1200);
      expect(Energy.tdee(1000, ActivityLevel.light), 1375);
      expect(Energy.tdee(1000, ActivityLevel.moderate), 1550);
      expect(Energy.tdee(1000, ActivityLevel.active), 1725);
      expect([
        for (final g in HealthGoal.values)
          Energy.dailyTarget(2000, g.energyAdjustment)
      ], [
        1700,
        2000,
        2100,
        2200
      ]);
      expect(Energy.roundForDisplay(1964.9), 1960);
      expect(Energy.roundForDisplay(1965), 1970);
    });

    test('age 13–100 only', () {
      final now = DateTime(2026, 10, 17);
      expect(Energy.ageFrom(1997, now: now), 29);
      expect(Energy.isValidBirthYear(2013, now: now), isTrue);
      expect(Energy.isValidBirthYear(2014, now: now), isFalse);
      expect(Energy.isValidBirthYear(1926, now: now), isTrue);
      expect(Energy.isValidBirthYear(1925, now: now), isFalse);
    });

    test('the profile computes its need; legacy profiles have none', () {
      final me = HealthProfileDto.fromJson(
              mockHealthProfileJsonFor('u_me', syncProvider: 'none')!)
          .toEntity();
      expect(me.gender, Gender.female);
      expect(me.birthYear, 1997);
      expect(me.activityLevel, ActivityLevel.light);
      final age = Energy.ageFrom(1997);
      final bmr = 10 * 66 + 6.25 * 172 - 5 * age - 161;
      expect(me.bmr, bmr);
      expect(me.tdee, bmr * 1.375);
      // Nearest 10 kcal, from the unrounded need.
      expect(me.dailyKcalTarget, (bmr * 1.375 * 1.05 / 10).round() * 10);

      final tam = HealthProfileDto.fromJson(
              mockHealthProfileJsonFor('u_chef_tam', syncProvider: 'none')!)
          .toEntity();
      expect(tam.hasEnergyInputs, isFalse);
      expect(tam.tdee, isNull);
      expect(tam.dailyKcalTarget, isNull);
      expect(tam.mealPattern, MealPattern.standard);
    });
  });

  group('health profile wire format', () {
    test('allergies: legacy ids and {allergenId, name}; custom names kept', () {
      final dto = HealthProfileDto.fromJson({
        'heightCm': 160,
        'weightKg': 50,
        'goal': 'maintain',
        'allergies': [
          'peanut',
          {'allergenId': 'soy', 'name': 'Đậu nành'},
          {'allergenId': 'mushroom', 'name': 'Nấm'},
          {'allergenId': null, 'name': 'lá lốt'},
          {'allergenId': 'peanut', 'name': 'Đậu phộng'}, // duplicate
        ],
        'mealPattern': 'dinner,breakfast,snack_pm',
      });
      expect(dto.allergies, ['peanut', 'soy', 'Nấm', 'lá lốt']);
      expect(dto.toEntity().mealPattern,
          [MealSlot.breakfast, MealSlot.snackPm, MealSlot.dinner]);
      expect(dto.toJson()['allergies'], [
        {'allergenId': 'peanut', 'name': 'Đậu phộng'},
        {'allergenId': 'soy', 'name': 'Đậu nành'},
        {'allergenId': null, 'name': 'Nấm'},
        {'allergenId': null, 'name': 'lá lốt'},
      ]);
      final request = _request(
          allergies: const ['peanut', 'lá lốt'],
          pattern: const [MealSlot.dinner, MealSlot.lunch]).toJson();
      expect(request['mealPattern'], ['lunch', 'dinner']);
      expect(request.containsKey('gender'), isFalse, reason: 'unchanged');
    });

    test('a profile without a pattern has 3 meals', () {
      final dto = HealthProfileDto.fromJson(
          {'heightCm': 160, 'weightKg': 50, 'goal': 'maintain'});
      expect(dto.toEntity().mealPattern, MealPattern.standard);
      expect(dto.toEntity().gender, isNull);
    });

    test('PUT validates the birth year and the pattern; keeps the rest',
        () async {
      final repo = MockMealPlannerRepository(userId: 'u_me', clock: () => _wed);
      await expectLater(
          repo.updateHealthProfile(_request(birthYear: 2020)), _apiError(400));
      await expectLater(repo.updateHealthProfile(_request(pattern: const [])),
          _apiError(400));
      final saved = await repo
          .updateHealthProfile(_request(allergies: const ['peanut', 'lá lốt']));
      expect(saved.gender, 'Female', reason: 'not sent → kept');
      expect(saved.birthYear, 1997);
      expect(saved.mealPattern, ['breakfast', 'lunch', 'snack_pm', 'dinner']);
      expect(saved.allergies, ['peanut', 'lá lốt']);
      expect(saved.tdee, isNotNull);
      expect(saved.bmr, isNotNull);
    });
  });

  group('meals of the day', () {
    test('presets and kcal weights 25/10/35/10/30/8, normalised', () {
      expect(MealPatternPreset.of(const [MealSlot.dinner, MealSlot.lunch]),
          MealPatternPreset.two);
      expect(
          MealPatternPreset.of(MealPattern.standard), MealPatternPreset.three);
      expect(MealPattern.label(const [MealSlot.lunch, MealSlot.snackLate]),
          'Tuỳ chỉnh · 2 bữa');
      final three = MealPattern.kcalTargets(MealPattern.standard, 1800);
      expect(three, {
        MealSlot.breakfast: 500,
        MealSlot.lunch: 700,
        MealSlot.dinner: 600,
      });
      final five =
          MealPattern.kcalTargets(MealPatternPreset.fiveSmall.slots, 2200);
      expect(five.values.fold<int>(0, (a, b) => a + b), closeTo(2200, 2));
    });

    test('Minh Anh\'s week follows her "3 bữa + 1 phụ"', () async {
      final plan =
          (await MockMealPlannerRepository(userId: 'u_me', clock: () => _wed)
                  .getCurrentMealPlan())!
              .toEntity();
      for (final day in plan.days) {
        expect(day.meals.keys, [
          MealSlot.breakfast,
          MealSlot.lunch,
          MealSlot.snackPm,
          MealSlot.dinner,
        ]);
      }
      // Tâm keeps 3 meals.
      final tam = (await MockMealPlannerRepository(
              userId: 'u_chef_tam', clock: () => _wed).getCurrentMealPlan())!
          .toEntity();
      expect(tam.days.first.meals.keys,
          [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner]);
    });

    test('"2 bữa": 2 slots a day, portions keep the day ≈ its kcal target',
        () async {
      final repo = MockMealPlannerRepository(userId: 'u_me', clock: () => _wed);
      await repo
          .updateHealthProfile(_request(pattern: MealPatternPreset.two.slots));
      final plan = await repo.generateMealPlan(startDate: startOfWeek(_wed));
      final target = plan.dailyTargets.calories;
      final profile = (await repo.getHealthProfile())!.toEntity();
      expect(target, profile.dailyKcalTarget);
      for (final day in plan.days) {
        expect(day.meals.keys.toSet(), {'lunch', 'dinner'});
        expect((_kcal(day) - target).abs() / target, lessThan(0.1),
            reason: '${day.date}: ${_kcal(day)} vs $target');
        for (final r in day.meals.values) {
          expect(r.allergens, isNot(contains('peanut')), reason: r.name);
        }
      }
      // Bigger portions are said so: "1,75 phần".
      final portions = {
        for (final d in plan.days)
          for (final r in d.meals.values) r.toEntity().portionLabel
      };
      expect(portions.whereType<String>(), isNotEmpty);
    });

    test('changing the pattern in the planner regenerates the week', () async {
      final container = await _container();
      container.listen(mealPlanControllerProvider, (_, __) {});
      final before = await container.read(mealPlanControllerProvider.future);
      expect(before.slotsFor(before.selectedDay!), hasLength(4));
      await container
          .read(mealPlanControllerProvider.notifier)
          .updateHealthProfile(
            heightCm: 172,
            weightKg: 66,
            goal: HealthGoal.leanMuscle,
            allergies: const ['peanut'],
            dietaryRestrictions: const [],
            mealPattern: MealPatternPreset.two.slots,
          );
      final after = await container.read(mealPlanControllerProvider.future);
      expect(after.pattern, [MealSlot.lunch, MealSlot.dinner]);
      for (final day in after.plan!.days) {
        expect(after.slotsFor(day), [MealSlot.lunch, MealSlot.dinner]);
      }
      expect(after.plan!.id, isNot(before.plan!.id));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('an extra meal belongs to one day and goes with its dish', () async {
      final container = await _container();
      container.listen(mealPlanControllerProvider, (_, __) {});
      await container.read(mealPlanControllerProvider.future);
      final notifier = container.read(mealPlanControllerProvider.notifier);
      expect(
          container.read(mealPlanControllerProvider).requireValue.selectedDate,
          dateOnly(_wed));
      final added = await notifier.addManualMeal(
          slot: MealSlot.snackAm, name: 'Bánh chuối hấp', calories: 180);
      expect(added.replaced, isNull);
      var s = container.read(mealPlanControllerProvider).requireValue;
      expect(s.slotsFor(s.selectedDay!), contains(MealSlot.snackAm));
      expect(s.isExtraSlot(MealSlot.snackAm), isTrue);
      final thursday = s.plan!.dayFor(_wed.add(const Duration(days: 1)))!;
      expect(s.slotsFor(thursday), isNot(contains(MealSlot.snackAm)));
      expect(thursday.missingSlots(s.pattern),
          [MealSlot.snackAm, MealSlot.snackLate]);

      await notifier.removeMeal(MealSlot.snackAm);
      s = container.read(mealPlanControllerProvider).requireValue;
      expect(s.slotsFor(s.selectedDay!), isNot(contains(MealSlot.snackAm)));
    });
  });

  group('add-meal API (for a delivered chef plan)', () {
    test('dishes land by date and slot with the chef; other weeks skipped',
        () async {
      final container = await _container();
      container.listen(mealPlanControllerProvider, (_, __) {});
      await container.read(mealPlanControllerProvider.future);
      final thursday = DateTime(2026, 10, 15);
      final placed =
          await container.read(mealPlanControllerProvider.notifier).addMeals([
        AddMealRequestDto(
          date: _wed,
          slot: MealSlot.dinner,
          name: 'Cơm gạo lứt đậu hũ non sốt nấm',
          source: MealSource.chef.apiValue,
          sourceId: 'cs_tam_com_dau_hu_nam',
          sourceName: 'Lê Quang Tâm',
        ),
        AddMealRequestDto(
          date: thursday,
          slot: MealSlot.snackLate,
          name: 'Sữa hạt óc chó ấm',
          calories: 200,
          source: MealSource.chef.apiValue,
          sourceName: 'Lê Quang Tâm',
        ),
        AddMealRequestDto(
          date: DateTime(2026, 11, 2),
          slot: MealSlot.lunch,
          name: 'Ngoài tuần này',
          source: MealSource.chef.apiValue,
        ),
      ]);
      expect(placed, 2);
      final s = container.read(mealPlanControllerProvider).requireValue;
      final dinner = s.plan!.dayFor(_wed)!.meals[MealSlot.dinner]!;
      expect(dinner.id, 'cs_tam_com_dau_hu_nam');
      expect(dinner.source, MealSource.chef);
      expect(dinner.sourceName, 'Lê Quang Tâm');
      expect(dinner.nutrition.proteinG, 28, reason: 'the recipe keeps macros');
      final late = s.plan!.dayFor(thursday)!.meals[MealSlot.snackLate]!;
      expect(late.source, MealSource.chef);
      expect(late.nutrition.proteinG, isNull, reason: 'none invented');
      expect(s.isExtraSlot(MealSlot.snackLate), isTrue);
    });

    test('a 7-day × 4-meal plan goes in one batched request', () async {
      final api = _CountingPlanner();
      final scoped = ProviderContainer(overrides: [
        sharedPreferencesProvider.overrideWithValue(await _prefs(_minhAnh)),
        plannerClockProvider.overrideWithValue(() => _wed),
        mealPlannerApiProvider.overrideWithValue(api),
      ]);
      addTearDown(scoped.dispose);
      scoped.listen(mealPlanControllerProvider, (_, __) {});
      await scoped.read(mealPlanControllerProvider.future);
      final monday = DateTime(2026, 10, 12);
      const slots = [
        MealSlot.breakfast,
        MealSlot.lunch,
        MealSlot.snackPm,
        MealSlot.dinner,
      ];
      final requests = [
        for (var d = 0; d < 7; d++)
          for (final slot in slots)
            AddMealRequestDto(
              date: monday.add(Duration(days: d)),
              slot: slot,
              name: 'Món chuyên gia ${d + 1}-${slot.apiValue}',
              calories: 400,
              source: MealSource.chef.apiValue,
              sourceName: 'ThS. DD Phạm Thu Hà',
            ),
        // Day 8 is next week: skipped, not an error.
        AddMealRequestDto(
          date: DateTime(2026, 10, 19),
          slot: MealSlot.lunch,
          name: 'Ngoài tuần này',
          source: MealSource.chef.apiValue,
        ),
      ];

      final placed = await scoped
          .read(mealPlanControllerProvider.notifier)
          .addMeals(requests);

      expect(placed, 28);
      expect(api.batchCalls, 1, reason: 'one round trip, not one per meal');
      expect(api.singleCalls, 0);
      final plan = scoped.read(mealPlanControllerProvider).requireValue.plan!;
      for (var d = 0; d < 7; d++) {
        final day = plan.dayFor(monday.add(Duration(days: d)))!;
        for (final slot in slots) {
          expect(day.meals[slot]?.name,
              'Món chuyên gia ${d + 1}-${slot.apiValue}');
          expect(day.meals[slot]?.source, MealSource.chef);
          expect(day.meals[slot]?.sourceName, 'ThS. DD Phạm Thu Hà');
        }
      }
      expect(
          await scoped.read(mealPlanControllerProvider.notifier).addMeals([]),
          0);
      expect(api.batchCalls, 1, reason: 'nothing to send, no request');
    });

    test('batch: #fail in any dish → 503 and nothing is placed', () async {
      final repo = MockMealPlannerRepository(userId: 'u_me', clock: () => _wed);
      final before = (await repo.getCurrentMealPlan())!
          .days
          .firstWhere((d) => isSameDay(d.date, _wed))
          .meals['dinner']
          ?.name;
      await expectLater(
        repo.addMealsToCurrentPlan([
          AddMealRequestDto(
              date: _wed, slot: MealSlot.dinner, name: 'Đậu hũ sốt cà'),
          AddMealRequestDto(
              date: _wed, slot: MealSlot.lunch, name: 'Món lỗi #fail'),
        ]),
        _apiError(503),
      );
      final after = (await repo.getCurrentMealPlan())!
          .days
          .firstWhere((d) => isSameDay(d.date, _wed))
          .meals['dinner']
          ?.name;
      expect(after, before);

      final result = await repo.addMealsToCurrentPlan([
        AddMealRequestDto(
            date: _wed, slot: MealSlot.dinner, name: 'Đậu hũ sốt cà'),
        AddMealRequestDto(
            date: DateTime(2026, 11, 2), slot: MealSlot.lunch, name: 'Sau'),
      ]);
      expect(result.placed, 1);
      expect(result.skipped, 1);
      expect(result.days.single.meals['dinner']?.name, 'Đậu hũ sốt cà');
      final json = AddMealsResultDto.fromJson(result.toJson());
      expect((json.placed, json.skipped, json.days.length), (1, 1, 1));
    });
  });

  group('free-text allergies', () {
    test('"lá lốt" (accents optional) flags matching dishes', () {
      const dish = Recipe(
        id: 'ds5',
        name: 'Đậu hũ cuốn lá lốt nướng',
        nutrition: Nutrition(calories: 520),
        allergens: ['soy'],
      );
      expect(dish.allergenConflicts(['lá lốt']), ['lá lốt']);
      expect(dish.allergenConflicts(['la lot']), ['la lot']);
      expect(dish.allergenConflicts(['soy', 'lá lốt']), ['soy', 'lá lốt']);
      expect(dish.allergenConflicts(['lá']), ['lá'], reason: 'whole word');
      expect(dish.allergenConflicts(['lốt cuốn']), isEmpty);
      // Short words keep their accents: "bơ" is not "bò".
      expect(mentionsAllergy('Bơ', ['Bò lúc lắc chay']), isFalse);
      expect(mentionsAllergy('Bơ', ['Sinh tố bơ sữa hạt']), isTrue);
      // Tagged ids only match tags.
      expect(
          const Recipe(
                  id: 'x',
                  name: 'Đậu hũ chiên',
                  nutrition: Nutrition(calories: 300))
              .allergenConflicts(['soy']),
          isEmpty);
    });

    test('the planner flags them and AI suggestions avoid them', () async {
      final repo = MockMealPlannerRepository(userId: 'u_me', clock: () => _wed);
      await repo.updateHealthProfile(
          _request(allergies: const ['peanut', 'lá lốt', 'Nấm']));
      final plan = (await repo.getCurrentMealPlan())!;
      final monday = plan.days.first.date;
      final day = await repo.swapMeal(
          planId: plan.id,
          request: SwapMealRequestDto(
              date: monday, slot: MealSlot.dinner, recipeId: 'ds5'));
      expect(day.toEntity().conflictCount(['lá lốt']), greaterThanOrEqualTo(1));
      final swaps = await repo.getSwapSuggestions(
          planId: plan.id, date: monday, slot: MealSlot.dinner);
      for (final r in swaps) {
        expect(r.name.toLowerCase(), isNot(contains('lá lốt')));
        expect(r.name.toLowerCase(), isNot(contains('nấm')));
      }
      final generated =
          await repo.generateMealPlan(startDate: startOfWeek(_wed));
      for (final d in generated.days) {
        for (final r in d.meals.values) {
          expect(
              allergyConflicts(
                  tags: r.allergens,
                  texts: [r.name],
                  userAllergies: const ['peanut', 'lá lốt', 'Nấm']),
              isEmpty,
              reason: r.name);
        }
      }
    });
  });

  group('screens', () {
    testWidgets(
        'Hồ sơ sức khoẻ: gender, birth year, activity, energy need; year '
        'and meal checks; free-text allergy', (tester) async {
      await _pump(tester, const HealthProfileEditScreen(),
          size: const Size(411, 2400));
      await _wait(tester, 1500);
      final age = Energy.ageFrom(1997);
      expect(find.text('$age tuổi'), findsOneWidget);
      final me = Energy.tdee(
          Energy.bmr(
              gender: Gender.female, weightKg: 66, heightCm: 172, age: age),
          ActivityLevel.light);
      expect(
          find.text(
              'Nhu cầu ≈ ${formatInt(Energy.roundForDisplay(me))} kcal/ngày'),
          findsOneWidget);
      for (final label in ['Nam', 'Nữ', 'Khác', 'Ít', 'Nhẹ', 'Vừa', 'Nhiều']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      // "Khác" uses the mean constant: −78 instead of −161.
      await tester.tap(find.text('Khác'));
      await tester.pump();
      final other = Energy.tdee(
          Energy.bmr(
              gender: Gender.other, weightKg: 66, heightCm: 172, age: age),
          ActivityLevel.light);
      expect(
          find.text(
              'Nhu cầu ≈ ${formatInt(Energy.roundForDisplay(other))} kcal/ngày'),
          findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Năm sinh'), '2020');
      await tester.pump();
      expect(find.text('Năm sinh không hợp lệ (13–100 tuổi)'), findsOneWidget);
      expect(
          find.text(
              'Thêm giới tính và năm sinh để tính nhu cầu năng lượng chính xác hơn'),
          findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Năm sinh'), '1990');
      await tester.pump();
      expect(find.text('Năm sinh không hợp lệ (13–100 tuổi)'), findsNothing);
      expect(find.text('${Energy.ageFrom(1990)} tuổi'), findsOneWidget);

      // Free text: Enter keeps the member's own words.
      final allergy = find.byKey(const ValueKey('allergy-input'));
      await tester.enterText(allergy, 'rau răm');
      await _wait(tester, 750);
      expect(find.text('Thêm «rau răm»'), findsOneWidget);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _wait(tester, 750);
      expect(find.widgetWithText(InputChip, 'rau răm'), findsOneWidget);
      // A catalog name typed without accents becomes the catalog allergen.
      await tester.enterText(allergy, 'la lot');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _wait(tester, 750);
      expect(find.widgetWithText(InputChip, 'Lá lốt'), findsOneWidget);
      await tester.tap(find.byTooltip('Bỏ Đậu phộng'));
      await tester.pump();
      expect(find.widgetWithText(InputChip, 'Đậu phộng'), findsNothing);

      // Meals of the day: presets, at least one.
      expect(find.widgetWithText(ChoiceChip, '3 bữa + 1 phụ'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '2 bữa'));
      await tester.pump();
      expect(
          find.text(
              'Lưu xong, thực đơn tuần này sẽ được tạo lại theo các bữa mới.'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(FilterChip, 'Bữa trưa'));
      await tester.tap(find.widgetWithText(FilterChip, 'Bữa tối'));
      await tester.pump();
      expect(find.text('Chọn ít nhất 1 bữa'), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Lưu'))
              .onPressed,
          isNull);
      await tester.tap(find.widgetWithText(FilterChip, 'Phụ tối'));
      await tester.pump();
      expect(find.text('Chọn ít nhất 1 bữa'), findsNothing);
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Lưu'))
              .onPressed,
          isNotNull);
      await _wait(tester, 1000);
    });

    testWidgets('a legacy profile is asked for gender and birth year',
        (tester) async {
      await _pump(tester, const MealPlannerScreen(),
          session: _tam, size: const Size(411, 1800));
      await _wait(tester, 3000);
      expect(
          find.text(
              'Thêm giới tính và năm sinh để tính nhu cầu năng lượng chính xác hơn'),
          findsOneWidget);
      await _wait(tester, 1000);
    });

    testWidgets(
        'Thực đơn: her snack slot shows; "Thêm bữa" adds a meal to this day '
        'only, marked "bữa thêm" with "Bỏ món"', (tester) async {
      await _pump(tester, const MealPlannerScreen(),
          size: const Size(411, 2600));
      await _wait(tester, 3000);
      expect(find.byTooltip('Đổi phụ chiều'), findsOneWidget);
      expect(find.byTooltip('Bỏ món phụ chiều'), findsNothing,
          reason: 'in her pattern, not an extra');
      final energy = find.textContaining('Nhu cầu ≈', findRichText: true);
      expect(energy, findsOneWidget);

      final addMeal = find.widgetWithText(OutlinedButton, 'Thêm bữa');
      await tester.ensureVisible(addMeal);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(addMeal);
      await _wait(tester, 750);
      expect(find.text('Thêm bữa cho ${formatLongDate(_wed)}'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Phụ sáng'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Phụ tối'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Bữa trưa'), findsNothing);
      await tester.tap(find.widgetWithText(ListTile, 'Phụ sáng'));
      await _wait(tester, 1500);
      expect(find.byType(MealPickerSheet), findsOneWidget);
      expect(find.text('Thêm phụ sáng'), findsOneWidget);
      await tester.tap(find.text('Tự nhập món'));
      await _wait(tester, 500);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên món'), 'Bánh chuối hấp');
      final submit = find.widgetWithText(FilledButton, 'Thêm vào phụ sáng');
      await tester.ensureVisible(submit);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(submit);
      await _wait(tester, 1500);
      expect(find.text('Bánh chuối hấp'), findsOneWidget);
      expect(find.textContaining('Phụ sáng (bữa thêm)', findRichText: true),
          findsOneWidget);
      expect(find.byTooltip('Bỏ món phụ sáng'), findsOneWidget);
      await tester.tap(find.byTooltip('Bỏ món phụ sáng'));
      await _wait(tester, 2000);
      expect(find.text('Đã bỏ món khỏi phụ sáng'), findsOneWidget);
      expect(find.text('Bánh chuối hấp'), findsNothing);
      expect(find.byTooltip('Đổi phụ sáng'), findsNothing);
      await _wait(tester, 6000); // snackbars
    });
  });
}
