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

    beTest('fields left out keep their saved value (B9 workaround)', () async {
      await planner.updateHealthProfile(request());
      final saved = await planner.updateHealthProfile(request(
          gender: null, birthYear: null, activity: null, pattern: null));
      expect(saved.gender, 'Female');
      expect(saved.birthYear, 1997);
      expect(saved.activityLevel, 'light');
      expect(saved.mealPattern, ['breakfast', 'lunch', 'dinner']);
    });

    beTest('the goal moves the target: lose is about 15 % under maintain',
        () async {
      final keep = await planner.updateHealthProfile(request());
      final lose = await planner
          .updateHealthProfile(request(goal: HealthGoal.loseWeight));
      final gain = await planner
          .updateHealthProfile(request(goal: HealthGoal.gainWeight));
      expect(lose.goal, 'lose');
      expect(gain.goal, 'gain');
      final maintain = keep.targetCalories!;
      expect(lose.targetCalories, closeTo(maintain * 0.85, 15));
      expect(gain.targetCalories, greaterThan(maintain));
      await planner.updateHealthProfile(request());
    });

    beTest('metrics emulation: a new weight is a real row, the same one local',
        () async {
      await planner.updateHealthProfile(request());
      final logged = await planner
          .logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 64.2));
      expect(logged.measurement.id, isNot(startsWith('local_')));
      expect(logged.measurement.weightKg, 64.2);
      expect(logged.profile.weightKg, 64.2);

      final same = await planner
          .logBodyMeasurement(const LogMeasurementRequestDto(weightKg: 64.2));
      expect(same.measurement.id, startsWith('local_'));
      expect(same.measurement.weightKg, 64.2);

      final history = await planner.getBodyMeasurements();
      expect(history.first.weightKg, 64.2);
      expect(history.where((m) => m.id.startsWith('local_')), isEmpty);
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
