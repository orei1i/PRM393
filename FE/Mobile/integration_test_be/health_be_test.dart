// integration_test_be/health_be_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:veganlife_mobile/features/meal_planner/data/allergen_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/meal_planner_api_service.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/body_measurement_model.dart';
import 'package:veganlife_mobile/features/meal_planner/data/models/health_profile_model.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/health_profile.dart';
import 'package:veganlife_mobile/features/meal_planner/domain/entities/meal_plan.dart';

import 'be_harness.dart';

Future<void> main() async {
  final be = await BeHarness.start();

  group('health', skip: be.skipReason, () {
    late BeUser me;
    late MealPlannerApiService planner;

    UpdateHealthProfileRequestDto request({
      double weightKg = 66,
      HealthGoal goal = HealthGoal.maintain,
      Gender? gender = Gender.female,
      int? birthYear = 1997,
      ActivityLevel? activity = ActivityLevel.light,
      List<MealSlot>? pattern = const [
        MealSlot.breakfast,
        MealSlot.lunch,
        MealSlot.dinner,
      ],
    }) =>
        UpdateHealthProfileRequestDto(
          heightCm: 170,
          weightKg: weightKg,
          goal: goal,
          allergies: const ['peanut', 'lá lốt'],
          dietaryRestrictions: const [],
          gender: gender,
          birthYear: birthYear,
          activityLevel: activity,
          mealPattern: pattern,
        );

    setUpAll(() async {
      me = await be.newUser(name: 'FE IT Health');
      planner = RemoteMealPlannerApiService(me.dio);
    });

    beTest('a new account has no profile and no history', () async {
      expect(await planner.getHealthProfile(), isNull);
      expect(await planner.getBodyMeasurements(), isEmpty);
    });

    beTest('a weigh-in without a profile is refused in Vietnamese', () async {
      await expectApiError(
        planner
            .logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 60)),
        status: 404,
      );
      expect(await planner.getBodyMeasurements(), isEmpty);
    });

    beTest('B9: a first profile must say gender and birth year', () async {
      final other = await be.newUser(name: 'FE IT Health First');
      await expectApiError(
        RemoteMealPlannerApiService(other.dio)
            .updateHealthProfile(request(gender: null, birthYear: null)),
        status: 400,
        message: 'Giới tính và năm sinh là bắt buộc khi tạo hồ sơ lần đầu.',
      );
    });

    beTest('PUT creates the profile: allergies, gender, year, pattern',
        () async {
      final saved = await planner.updateHealthProfile(request());
      expect(saved.allergies, containsAll(['peanut', 'lá lốt']));
      expect(saved.gender, 'Female');
      expect(saved.birthYear, 1997);
      expect(saved.activityLevel, 'light');
      expect(saved.mealPattern, ['breakfast', 'lunch', 'dinner']);
      expect(saved.bmi, closeTo(22.8, 0.1));
      expect(saved.targetCalories, greaterThan(1000));

      final read = await planner.getHealthProfile();
      expect(read!.allergies, containsAll(['peanut', 'lá lốt']));
    });

    beTest('B9: fields left out keep their saved value', () async {
      await planner
          .updateHealthProfile(request(activity: ActivityLevel.active));
      final saved = await planner.updateHealthProfile(request(
          gender: null, birthYear: null, activity: null, pattern: null));
      expect(saved.gender, 'Female');
      expect(saved.birthYear, 1997);
      expect(saved.activityLevel, 'active', reason: 'the app sends it back');
      expect(saved.mealPattern, ['breakfast', 'lunch', 'dinner']);
      await planner.updateHealthProfile(request());
    });

    beTest('B10: each goal is saved and moves the target', () async {
      final keep = await planner.updateHealthProfile(request());
      final maintain = keep.targetCalories!;
      for (final (goal, share) in [
        (HealthGoal.loseWeight, 0.85),
        (HealthGoal.leanMuscle, 1.05),
        (HealthGoal.gainWeight, 1.10),
        (HealthGoal.maintain, 1.0),
      ]) {
        final saved = await planner.updateHealthProfile(request(goal: goal));
        expect(saved.goal, goal.apiValue);
        expect(saved.targetCalories, closeTo(maintain * share, 15),
            reason: goal.apiValue);
        expect(saved.toEntity().goal, goal);
      }
    });

    beTest('B10: anything else is a Vietnamese 400', () async {
      for (final goal in ['lose', 'gain', 'khong-co']) {
        final res = await me.raw('PUT', '/health-profile/me',
            data: {...request().toJson(), 'goal': goal});
        expect(res.status, 400, reason: goal);
        expect(res.json['message'], contains('Mục tiêu'));
      }
    });

    beTest('B10: the two goals the app has no choice for read sensibly',
        () async {
      for (final (goal, shown) in [
        ('gain_muscle', HealthGoal.leanMuscle),
        ('eat_clean', HealthGoal.maintain),
      ]) {
        final res = await me.raw('PUT', '/health-profile/me',
            data: {...request().toJson(), 'goal': goal});
        expect(res.status, 200);
        final read = (await planner.getHealthProfile())!.toEntity();
        expect(read.goal, shown);
      }
      await planner.updateHealthProfile(request());
    });

    beTest('a weigh-in: logged, read back, the target moves', () async {
      final before = await planner.updateHealthProfile(request());
      final logged = await planner
          .logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 80));
      expect(logged.measurement.weightKg, 80);
      expect(logged.profile.weightKg, 80);
      expect(logged.profile.targetCalories, greaterThan(before.targetCalories!),
          reason: 'B37');

      final history = await planner.getBodyMeasurements();
      expect(history.first.id, logged.measurement.id);
      expect(history.where((m) => m.weightKg == 80), hasLength(1),
          reason: 'no second row from the PUT');
      expect((await planner.getHealthProfile())!.activityLevel, 'light');
    });

    beTest('the same weight is one more row: a check-in is a record', () async {
      final before = (await planner.getBodyMeasurements()).length;
      await planner
          .logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 80));
      expect(await planner.getBodyMeasurements(), hasLength(before + 1));
    });

    beTest('B36: nothing the BE would store blindly is sent', () async {
      final before = await planner.getBodyMeasurements();
      for (final bad in const [
        LogMeasurementRequestDto(weightKg: -5),
        LogMeasurementRequestDto(weightKg: 1000),
      ]) {
        await expectApiError(planner.logBodyMeasurement(bad),
            status: 400, code: 'invalid_measurement');
      }
      expect(await planner.getBodyMeasurements(), hasLength(before.length));
      expect((await planner.getHealthProfile())!.weightKg, 80);
    });

    beTest('B20: the BE filters by q too', () async {
      Future<List<Object?>> ids(String q) async =>
          (await rawRequest('GET', '/catalog/allergens', query: {'q': q}))
              .dataList
              .map((a) => a['allergenId'])
              .toList();
      expect(await ids('dau phong'), ['peanut']);
      expect(await ids('khong co chat nay'), isEmpty);
    });

    beTest('the allergen catalog is searched on the device', () async {
      final allergens = RemoteAllergenApiService(me.dio);
      expect((await allergens.search('lạc')).single.key, 'peanut');
      expect((await allergens.search('dau phong')).single.key, 'peanut');
      expect(await allergens.search(''), isNotEmpty);
      expect(await allergens.search('khong co chat nay'), isEmpty);
    });

    beTest('a guest can read the allergen catalog', () async {
      final allergens = RemoteAllergenApiService(be.guestDio());
      expect(await allergens.search('lạc'), isNotEmpty);
    });
  });
}
